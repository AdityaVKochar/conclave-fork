//
//  ScreenCaptureManager.swift
//  Conclave
//
//  Coordinates whole-device screen sharing via a ReplayKit Broadcast Upload
//  Extension (NOT in-app RPScreenRecorder, which can only capture this app's own
//  window). Standing up an App-Group socket server, then presenting the system
//  broadcast picker, lets the user share ANY app / their whole screen - the
//  extension streams JPEG frames back over the socket, which we decode and feed
//  into the WebRTC screen producer. Mirrors the working react-native-webrtc flow.
//

#if SKIP
enum ScreenCaptureManager {
    static var onProjectionRevoked: (() -> Void)?

    static func requestCapture() async -> Bool { fatalError() }
    static func isCaptureActive() -> Bool { fatalError() }
    static func stopCapture() { fatalError() }
}
#endif

#if canImport(UIKit) && !SKIP
import UIKit
import ReplayKit
import WebRTC
import Combine
#endif

enum ScreenCaptureStartPolicy {
    static let startTimeoutNanoseconds = UInt64(12_000_000_000)

    static func shouldApplyTimeout(generation: Int, currentGeneration: Int, hasServer: Bool, isConnected: Bool) -> Bool {
        generation == currentGeneration && hasServer && !isConnected
    }
}

enum ScreenShareBroadcastLifecycleState: String {
    case idle
    case starting
    case active
    case reconnecting
    case stopped
}

enum ScreenShareLifecycleBusKeys {
    static let state = "conclave.screenShare.lifecycle.state"
    static let updatedAt = "conclave.screenShare.lifecycle.updatedAt"
    static let stopRequestedAt = "conclave.screenShare.lifecycle.stopRequestedAt"
}

enum ScreenCaptureReconnectPolicy {
    // The extension retries for six seconds. Leave enough room for scheduling
    // jitter when the main app transitions between foreground and background.
    static let graceNanoseconds = UInt64(8_000_000_000)

    static func shouldFinalizeDisconnect(
        generation: Int,
        currentGeneration: Int,
        hasServer: Bool,
        isConnected: Bool
    ) -> Bool {
        generation == currentGeneration && hasServer && !isConnected
    }
}

#if canImport(UIKit) && !SKIP

private final class ScreenShareFrameRateGate: @unchecked Sendable {
    private let lock = NSLock()
    private var minFrameIntervalNs: UInt64 = 41_666_666
    private var lastAcceptedFrameNs: UInt64 = 0

    func update(maxFrameRate: Double) {
        let clampedFrameRate = Swift.max(1.0, Swift.min(maxFrameRate, 60.0))
        let nextInterval = UInt64(1_000_000_000.0 / clampedFrameRate)
        lock.lock()
        minFrameIntervalNs = Swift.max(1, nextInterval)
        lastAcceptedFrameNs = 0
        lock.unlock()
    }

    func reset() {
        lock.lock()
        lastAcceptedFrameNs = 0
        lock.unlock()
    }

    func shouldAcceptFrame(
        nowNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if lastAcceptedFrameNs != 0,
           nowNanoseconds - lastAcceptedFrameNs < minFrameIntervalNs {
            return false
        }

        lastAcceptedFrameNs = nowNanoseconds
        return true
    }
}

/// Coalesces ReplayKit frames before they cross onto the main queue. JPEG
/// decoding can outpace both the MainActor and WebRTC's encoder, especially
/// for portrait device frames. Keeping only the newest pending frame prevents
/// an unbounded queue of retained pixel buffers while preserving the freshest
/// screen contents.
private final class ScreenShareLatestFramePump: @unchecked Sendable {
    typealias Delivery = @MainActor @Sendable (ScreenFrameBox) -> Void

    private let lock = NSLock()
    private var pendingFrame: ScreenFrameBox?
    private var deliveryScheduled = false

    func enqueue(_ frame: ScreenFrameBox, delivery: @escaping Delivery) {
        lock.lock()
        pendingFrame = frame
        let shouldSchedule = !deliveryScheduled
        if shouldSchedule {
            deliveryScheduled = true
        }
        lock.unlock()

        if shouldSchedule {
            scheduleDrain(delivery: delivery)
        }
    }

    func reset() {
        lock.lock()
        pendingFrame = nil
        lock.unlock()
    }

    private func scheduleDrain(delivery: @escaping Delivery) {
        DispatchQueue.main.async { [weak self] in
            self?.drain(delivery: delivery)
        }
    }

    @MainActor
    private func drain(delivery: @escaping Delivery) {
        lock.lock()
        guard let frame = pendingFrame else {
            deliveryScheduled = false
            lock.unlock()
            return
        }
        pendingFrame = nil
        lock.unlock()

        delivery(frame)

        lock.lock()
        let shouldContinue = pendingFrame != nil
        if !shouldContinue {
            deliveryScheduled = false
        }
        lock.unlock()

        if shouldContinue {
            scheduleDrain(delivery: delivery)
        }
    }
}

/// Manages screen capture coordination between the broadcast extension and WebRTC.
@MainActor
final class ScreenCaptureManager: NSObject {
    static let shared = ScreenCaptureManager()

    // MARK: - Configuration
    private let appGroupIdentifier = "group.com.acmvit.conclave.screenshare"
    private let broadcastExtensionBundleId = "com.acmvit.conclave.ScreenShareExtension"
    private let publishFrameRateKey = "conclave.screenShare.maxFrameRate"
    private let publishMaxWidthKey = "conclave.screenShare.maxWidth"
    private let publishMaxHeightKey = "conclave.screenShare.maxHeight"
    private let publishMaxBitrateKey = "conclave.screenShare.maxBitrateBps"
    private let publishContentHintKey = "conclave.screenShare.contentHint"

    // MARK: - Publishers
    let isCapturing = CurrentValueSubject<Bool, Never>(false)
    let captureError = PassthroughSubject<Error, Never>()

    /// Invoked when the broadcast ends from OUTSIDE the app (Control Center /
    /// status bar / the extension's own timeout) so the meeting can tear down
    /// its producer and reset UI state. Set by MeetingViewModel.
    var onBroadcastStopped: (() -> Void)?

    // MARK: - Properties
    private weak var webRTCClient: WebRTCClient?
    private var server: ScreenShareSocketServer?
    private var connected = false
    private var hasConnectedInCurrentCapture = false
    private var startGeneration = 0
    private var pendingStartContinuation: CheckedContinuation<Void, Error>?
    private var startTimeoutTask: Task<Void, Never>?
    private var reconnectGraceTask: Task<Void, Never>?
    private let frameGate = ScreenShareFrameRateGate()
    private let framePump = ScreenShareLatestFramePump()
    private var publishMaxFrameRate = 24.0
    private var publishMaxWidth = 3_840
    private var publishMaxHeight = 2_160
    private var publishMaxBitrateBps = 2_500_000
    private var publishContentHint = NativeScreenShareContentHint.detail.rawValue

    // MARK: - Public Methods

    var isCaptureActive: Bool {
        server != nil && (connected || reconnectGraceTask != nil)
    }

    func updateMaxFrameRate(_ maxFrameRate: Double) {
        updatePublishProfile(
            maxFrameRate: maxFrameRate,
            maxWidth: publishMaxWidth,
            maxHeight: publishMaxHeight,
            maxBitrateBps: publishMaxBitrateBps,
            contentHint: publishContentHint
        )
    }

    func updatePublishProfile(
        maxFrameRate: Double,
        maxWidth: Int,
        maxHeight: Int,
        maxBitrateBps: Int,
        contentHint: String
    ) {
        publishMaxFrameRate = max(1.0, min(maxFrameRate, 60.0))
        publishMaxWidth = max(320, min(maxWidth, 3_840))
        publishMaxHeight = max(180, min(maxHeight, 2_160))
        publishMaxBitrateBps = max(150_000, min(maxBitrateBps, 15_000_000))
        publishContentHint = contentHint
        frameGate.update(maxFrameRate: publishMaxFrameRate)
        server?.updateMaxResolution(width: publishMaxWidth, height: publishMaxHeight)

        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(publishMaxFrameRate, forKey: publishFrameRateKey)
            defaults.set(publishMaxWidth, forKey: publishMaxWidthKey)
            defaults.set(publishMaxHeight, forKey: publishMaxHeightKey)
            defaults.set(publishMaxBitrateBps, forKey: publishMaxBitrateKey)
            defaults.set(publishContentHint, forKey: publishContentHintKey)
        }
    }

    /// Stand up the socket server and present the system broadcast picker. The
    /// share becomes live once the user confirms the picker and the extension
    /// connects (frames then flow in via the server). Returns only after that
    /// connection is established, so callers do not mark the meeting as
    /// sharing when the user cancels the system sheet.
    func startCapture(webRTCClient: WebRTCClient) async throws {
        if server != nil {
            await stopCapture()
        }

        framePump.reset()
        self.webRTCClient = webRTCClient
        self.connected = false
        self.hasConnectedInCurrentCapture = false
        updatePublishProfile(
            maxFrameRate: webRTCClient.screenShareCaptureMaxFramerate,
            maxWidth: webRTCClient.screenShareCaptureMaxWidth,
            maxHeight: webRTCClient.screenShareCaptureMaxHeight,
            maxBitrateBps: publishMaxBitrateBps,
            contentHint: publishContentHint
        )
        startGeneration &+= 1
        let generation = startGeneration

        guard let server = ScreenShareSocketServer(appGroupIdentifier: appGroupIdentifier) else {
            throw ScreenCaptureError.appGroupUnavailable
        }
        server.updateMaxResolution(width: publishMaxWidth, height: publishMaxHeight)

        let started = server.start(
            onFrame: { [weak self] box in
                self?.framePump.enqueue(box) { [weak self] latestFrame in
                    guard self?.startGeneration == generation else { return }
                    self?.webRTCClient?.feedScreenFrame(latestFrame.frame)
                }
            },
            shouldDecodeFrame: { [frameGate] in
                frameGate.shouldAcceptFrame()
            },
            onConnect: { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.startGeneration == generation,
                          self.server != nil else { return }
                    self.reconnectGraceTask?.cancel()
                    self.reconnectGraceTask = nil
                    self.connected = true
                    self.hasConnectedInCurrentCapture = true
                    self.isCapturing.send(true)
                    self.finishPendingStart(.success(()))
                }
            },
            onDisconnect: { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard self?.startGeneration == generation else { return }
                    self?.scheduleReconnectGrace(generation: generation)
                }
            }
        )
        guard started else {
            server.stop()
            self.webRTCClient = nil
            frameGate.reset()
            throw ScreenCaptureError.socketUnavailable
        }
        self.server = server

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingStartContinuation = continuation

                if Task.isCancelled {
                    cancelPendingStart(generation: generation)
                    return
                }

                presentBroadcastPicker()

                // If the extension never connects (the user cancelled or dismissed
                // the system sheet), tear everything back down so the share button
                // never flips to a dead producer.
                scheduleStartTimeout(generation: generation)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelPendingStart(generation: generation)
            }
        }
    }

    /// Tear down from the app side (the in-app Share toggle). Closing the socket
    /// makes the extension's next write fail, which finishes the broadcast
    /// gracefully.
    func stopCapture() async {
        requestBroadcastStop()
        startGeneration &+= 1
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        reconnectGraceTask?.cancel()
        reconnectGraceTask = nil
        connected = false
        hasConnectedInCurrentCapture = false
        frameGate.reset()
        framePump.reset()
        server?.stop()
        server = nil
        webRTCClient = nil
        isCapturing.send(false)
        finishPendingStart(.failure(ScreenCaptureError.cancelled))
    }

    /// Reconcile the app's in-memory state with the extension-owned lifecycle
    /// record whenever iOS moves the app between foreground and background.
    /// Socket callbacks remain authoritative while connected; the shared record
    /// covers extension termination while the app was suspended.
    func reconcileBroadcastLifecycle() {
        guard server != nil, pendingStartContinuation == nil else { return }
        switch persistedBroadcastState {
        case .idle, .stopped:
            handleExternalStop()
        case .starting, .active, .reconnecting:
            if connected {
                isCapturing.send(true)
            } else if reconnectGraceTask == nil {
                scheduleReconnectGrace(generation: startGeneration)
            }
        }
    }

    // MARK: - Private

    private func handleExternalStop() {
        guard server != nil else { return }
        let hadConnected = hasConnectedInCurrentCapture
        startGeneration &+= 1
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        reconnectGraceTask?.cancel()
        reconnectGraceTask = nil
        connected = false
        hasConnectedInCurrentCapture = false
        frameGate.reset()
        framePump.reset()
        server?.stop()
        server = nil
        webRTCClient = nil
        isCapturing.send(false)
        finishPendingStart(.failure(ScreenCaptureError.cancelled))
        if hadConnected {
            onBroadcastStopped?()
        }
    }

    private func cancelPendingStart(generation: Int) {
        guard startGeneration == generation,
              pendingStartContinuation != nil else { return }
        startGeneration &+= 1
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        reconnectGraceTask?.cancel()
        reconnectGraceTask = nil
        connected = false
        hasConnectedInCurrentCapture = false
        frameGate.reset()
        framePump.reset()
        server?.stop()
        server = nil
        webRTCClient = nil
        isCapturing.send(false)
        finishPendingStart(.failure(ScreenCaptureError.cancelled))
    }

    private func finishPendingStart(_ result: Result<Void, Error>) {
        guard let continuation = pendingStartContinuation else { return }
        pendingStartContinuation = nil
        if case .success = result {
            startTimeoutTask?.cancel()
            startTimeoutTask = nil
        }
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func scheduleStartTimeout(generation: Int) {
        startTimeoutTask?.cancel()
        startTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: ScreenCaptureStartPolicy.startTimeoutNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  ScreenCaptureStartPolicy.shouldApplyTimeout(
                    generation: generation,
                    currentGeneration: self.startGeneration,
                    hasServer: self.server != nil,
                    isConnected: self.connected
                  ) else { return }
            self.handleExternalStop()
        }
    }

    private func scheduleReconnectGrace(generation: Int) {
        guard startGeneration == generation, server != nil else { return }
        connected = false
        reconnectGraceTask?.cancel()
        reconnectGraceTask = Task { @MainActor [weak self] in
            let pollInterval = UInt64(250_000_000)
            let pollCount = Int(ScreenCaptureReconnectPolicy.graceNanoseconds / pollInterval)
            for _ in 0..<pollCount {
                try? await Task.sleep(nanoseconds: pollInterval)
                guard !Task.isCancelled, let self else { return }
                if self.persistedBroadcastState == .stopped {
                    self.reconnectGraceTask = nil
                    self.handleExternalStop()
                    return
                }
                if self.connected { return }
            }
            guard !Task.isCancelled,
                  let self,
                  ScreenCaptureReconnectPolicy.shouldFinalizeDisconnect(
                    generation: generation,
                    currentGeneration: self.startGeneration,
                    hasServer: self.server != nil,
                    isConnected: self.connected
                  ) else { return }
            self.reconnectGraceTask = nil
            self.handleExternalStop()
        }
    }

    private var persistedBroadcastState: ScreenShareBroadcastLifecycleState {
        guard let rawValue = UserDefaults(suiteName: appGroupIdentifier)?
            .string(forKey: ScreenShareLifecycleBusKeys.state),
              let state = ScreenShareBroadcastLifecycleState(rawValue: rawValue) else {
            return .idle
        }
        return state
    }

    private func requestBroadcastStop() {
        guard server != nil else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(
            Date().timeIntervalSince1970,
            forKey: ScreenShareLifecycleBusKeys.stopRequestedAt
        )
    }

    private func presentBroadcastPicker() {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        picker.preferredExtension = broadcastExtensionBundleId
        picker.showsMicrophoneButton = false

        // The picker must be in the view hierarchy to present its system sheet.
        if let window = Self.keyWindow {
            window.addSubview(picker)
        }

        // Programmatically tap the internal button to surface the system sheet.
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                break
            }
        }

        // Remove the throwaway picker shortly after; the system sheet is its own
        // presentation and outlives this view.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            picker.removeFromSuperview()
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first
    }
}

// MARK: - Errors
enum ScreenCaptureError: Error, LocalizedError, Equatable {
    case appGroupUnavailable
    case socketUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Screen sharing is not configured (App Group unavailable)."
        case .socketUnavailable:
            return "Could not start screen sharing. Please try again."
        case .cancelled:
            return "Screen sharing was cancelled."
        }
    }
}

#endif
