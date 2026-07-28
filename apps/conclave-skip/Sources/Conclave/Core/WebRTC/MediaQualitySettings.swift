import Foundation

enum NativeMediaResolution: String, Codable, CaseIterable, Identifiable {
    case p360 = "360p"
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case p2160 = "2160p"

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .p360: return 640
        case .p720: return 1280
        case .p1080: return 1920
        case .p1440: return 2560
        case .p2160: return 3840
        }
    }

    var height: Int {
        switch self {
        case .p360: return 360
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .p2160: return 2160
        }
    }

    var label: String {
        switch self {
        case .p360: return "360p"
        case .p720: return "720p HD"
        case .p1080: return "1080p Full HD"
        case .p1440: return "1440p QHD"
        case .p2160: return "2160p 4K"
        }
    }
}

enum NativeCameraQualityPreset: String, Codable, CaseIterable, Identifiable {
    case auto
    case dataSaver = "data-saver"
    case highDefinition = "high-definition"
    case studio
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .dataSaver: return "Data saver"
        case .highDefinition: return "High definition"
        case .studio: return "Studio"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Balanced 720p at 30 fps"
        case .dataSaver: return "Clear video on limited data"
        case .highDefinition: return "Sharper 1080p detail"
        case .studio: return "Smooth 1080p at up to 60 fps"
        case .custom: return "Your advanced limits"
        }
    }
}

enum NativeScreenShareQualityPreset: String, Codable, CaseIterable, Identifiable {
    case auto
    case presentation
    case motion
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .presentation: return "Presentation"
        case .motion: return "Motion"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Balanced detail and cadence"
        case .presentation: return "Crisp text and slides"
        case .motion: return "Smoother demos and video"
        case .custom: return "Your advanced limits"
        }
    }
}

enum NativeCameraContentHint: String, Codable, CaseIterable, Identifiable {
    case motion
    case detail

    var id: String { rawValue }
    var label: String { self == .motion ? "Motion" : "Detail" }
}

enum NativeScreenShareContentHint: String, Codable, CaseIterable, Identifiable {
    case detail
    case text
    case motion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detail: return "Detail"
        case .text: return "Text"
        case .motion: return "Motion"
        }
    }
}

enum NativeMediaDegradationPreference: String, Codable, CaseIterable, Identifiable {
    case balanced
    case maintainFramerate = "maintain-framerate"
    case maintainResolution = "maintain-resolution"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .maintainFramerate: return "Keep frame rate"
        case .maintainResolution: return "Keep resolution"
        }
    }
}

enum NativeScreenShareCursorPreference: String, Codable, CaseIterable, Identifiable {
    case always
    case motion
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .always: return "Always"
        case .motion: return "While moving"
        case .never: return "Never"
        }
    }
}

struct NativeCameraQualitySettings: Codable, Equatable {
    var preset: NativeCameraQualityPreset
    var resolution: NativeMediaResolution
    var frameRate: Int
    var maxBitrateKbps: Int
    var contentHint: NativeCameraContentHint
    var degradationPreference: NativeMediaDegradationPreference

    init(
        preset: NativeCameraQualityPreset,
        resolution: NativeMediaResolution,
        frameRate: Int,
        maxBitrateKbps: Int,
        contentHint: NativeCameraContentHint,
        degradationPreference: NativeMediaDegradationPreference
    ) {
        self.preset = preset
        self.resolution = resolution
        self.frameRate = frameRate
        self.maxBitrateKbps = maxBitrateKbps
        self.contentHint = contentHint
        self.degradationPreference = degradationPreference
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case resolution
        case frameRate
        case maxBitrateKbps
        case contentHint
        case degradationPreference
    }

    init(from decoder: Decoder) throws {
        let fallback = NativeMediaQualityPolicy.defaultSettings.camera
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPreset = try? container.decode(String.self, forKey: .preset)
        let rawResolution = try? container.decode(String.self, forKey: .resolution)
        let rawContentHint = try? container.decode(String.self, forKey: .contentHint)
        let rawDegradation = try? container.decode(String.self, forKey: .degradationPreference)

        preset = NativeCameraQualityPreset(rawValue: rawPreset ?? "") ?? fallback.preset
        resolution = NativeMediaResolution(rawValue: rawResolution ?? "") ?? fallback.resolution
        frameRate = (try? container.decode(Int.self, forKey: .frameRate)) ?? fallback.frameRate
        maxBitrateKbps = (try? container.decode(Int.self, forKey: .maxBitrateKbps)) ?? fallback.maxBitrateKbps
        contentHint = NativeCameraContentHint(rawValue: rawContentHint ?? "") ?? fallback.contentHint
        degradationPreference = NativeMediaDegradationPreference(rawValue: rawDegradation ?? "") ?? fallback.degradationPreference
    }
}

struct NativeScreenShareQualitySettings: Codable, Equatable {
    var preset: NativeScreenShareQualityPreset
    var resolution: NativeMediaResolution
    var frameRate: Int
    var maxBitrateKbps: Int
    var contentHint: NativeScreenShareContentHint
    var degradationPreference: NativeMediaDegradationPreference
    var cursor: NativeScreenShareCursorPreference
    var includeAudio: Bool

    init(
        preset: NativeScreenShareQualityPreset,
        resolution: NativeMediaResolution,
        frameRate: Int,
        maxBitrateKbps: Int,
        contentHint: NativeScreenShareContentHint,
        degradationPreference: NativeMediaDegradationPreference,
        cursor: NativeScreenShareCursorPreference,
        includeAudio: Bool
    ) {
        self.preset = preset
        self.resolution = resolution
        self.frameRate = frameRate
        self.maxBitrateKbps = maxBitrateKbps
        self.contentHint = contentHint
        self.degradationPreference = degradationPreference
        self.cursor = cursor
        self.includeAudio = includeAudio
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case resolution
        case frameRate
        case maxBitrateKbps
        case contentHint
        case degradationPreference
        case cursor
        case includeAudio
    }

    init(from decoder: Decoder) throws {
        let fallback = NativeMediaQualityPolicy.defaultSettings.screenShare
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPreset = try? container.decode(String.self, forKey: .preset)
        let rawResolution = try? container.decode(String.self, forKey: .resolution)
        let rawContentHint = try? container.decode(String.self, forKey: .contentHint)
        let rawDegradation = try? container.decode(String.self, forKey: .degradationPreference)
        let rawCursor = try? container.decode(String.self, forKey: .cursor)

        preset = NativeScreenShareQualityPreset(rawValue: rawPreset ?? "") ?? fallback.preset
        resolution = NativeMediaResolution(rawValue: rawResolution ?? "") ?? fallback.resolution
        frameRate = (try? container.decode(Int.self, forKey: .frameRate)) ?? fallback.frameRate
        maxBitrateKbps = (try? container.decode(Int.self, forKey: .maxBitrateKbps)) ?? fallback.maxBitrateKbps
        contentHint = NativeScreenShareContentHint(rawValue: rawContentHint ?? "") ?? fallback.contentHint
        degradationPreference = NativeMediaDegradationPreference(rawValue: rawDegradation ?? "") ?? fallback.degradationPreference
        cursor = NativeScreenShareCursorPreference(rawValue: rawCursor ?? "") ?? fallback.cursor
        includeAudio = (try? container.decode(Bool.self, forKey: .includeAudio)) ?? fallback.includeAudio
    }
}

struct NativeMediaQualitySettings: Codable, Equatable {
    var camera: NativeCameraQualitySettings
    var screenShare: NativeScreenShareQualitySettings

    init(camera: NativeCameraQualitySettings, screenShare: NativeScreenShareQualitySettings) {
        self.camera = camera
        self.screenShare = screenShare
    }

    private enum CodingKeys: String, CodingKey {
        case camera
        case screenShare
    }

    init(from decoder: Decoder) throws {
        let fallback = NativeMediaQualityPolicy.defaultSettings
        let container = try decoder.container(keyedBy: CodingKeys.self)
        camera = (try? container.decode(NativeCameraQualitySettings.self, forKey: .camera)) ?? fallback.camera
        screenShare = (try? container.decode(NativeScreenShareQualitySettings.self, forKey: .screenShare)) ?? fallback.screenShare
    }
}

struct NativeResolvedCameraPublishSettings: Equatable {
    let width: Int
    let height: Int
    let frameRate: Int
    let maxBitrateBps: Int
    let contentHint: NativeCameraContentHint
    let degradationPreference: NativeMediaDegradationPreference
}

struct NativeResolvedScreenSharePublishSettings: Equatable {
    let idealWidth: Int
    let idealHeight: Int
    let maxWidth: Int
    let maxHeight: Int
    let frameRate: Int
    let maxBitrateBps: Int
    let contentHint: NativeScreenShareContentHint
    let degradationPreference: NativeMediaDegradationPreference
    let cursor: NativeScreenShareCursorPreference
    let includeAudio: Bool
}

enum NativeMediaQualityPolicy {
    static let cameraFrameRateOptions = [15, 20, 24, 30, 60]
    static let screenShareFrameRateOptions = [5, 10, 15, 24, 30, 60]

    static let defaultSettings = NativeMediaQualitySettings(
        camera: NativeCameraQualitySettings(
            preset: .auto,
            resolution: .p720,
            frameRate: 30,
            maxBitrateKbps: 1_650,
            contentHint: .motion,
            degradationPreference: .maintainFramerate
        ),
        screenShare: NativeScreenShareQualitySettings(
            preset: .auto,
            resolution: .p2160,
            frameRate: 24,
            maxBitrateKbps: 2_500,
            contentHint: .detail,
            degradationPreference: .maintainResolution,
            cursor: .always,
            includeAudio: true
        )
    )

    static func cameraPreset(
        _ preset: NativeCameraQualityPreset,
        current: NativeCameraQualitySettings
    ) -> NativeCameraQualitySettings {
        switch preset {
        case .auto:
            return defaultSettings.camera
        case .dataSaver:
            return NativeCameraQualitySettings(
                preset: .dataSaver,
                resolution: .p360,
                frameRate: 20,
                maxBitrateKbps: 260,
                contentHint: .motion,
                degradationPreference: .maintainFramerate
            )
        case .highDefinition:
            return NativeCameraQualitySettings(
                preset: .highDefinition,
                resolution: .p1080,
                frameRate: 30,
                maxBitrateKbps: 3_000,
                contentHint: .detail,
                degradationPreference: .balanced
            )
        case .studio:
            return NativeCameraQualitySettings(
                preset: .studio,
                resolution: .p1080,
                frameRate: 60,
                maxBitrateKbps: 4_000,
                contentHint: .motion,
                degradationPreference: .maintainFramerate
            )
        case .custom:
            var next = current
            next.preset = .custom
            return normalizedCamera(next)
        }
    }

    static func screenSharePreset(
        _ preset: NativeScreenShareQualityPreset,
        current: NativeScreenShareQualitySettings
    ) -> NativeScreenShareQualitySettings {
        switch preset {
        case .auto:
            return defaultSettings.screenShare
        case .presentation:
            return NativeScreenShareQualitySettings(
                preset: .presentation,
                resolution: .p2160,
                frameRate: 15,
                maxBitrateKbps: 3_500,
                contentHint: .text,
                degradationPreference: .maintainResolution,
                cursor: .always,
                includeAudio: true
            )
        case .motion:
            return NativeScreenShareQualitySettings(
                preset: .motion,
                resolution: .p1440,
                frameRate: 30,
                maxBitrateKbps: 4_500,
                contentHint: .motion,
                degradationPreference: .maintainFramerate,
                cursor: .motion,
                includeAudio: true
            )
        case .custom:
            var next = current
            next.preset = .custom
            return normalizedScreenShare(next)
        }
    }

    static func normalized(_ settings: NativeMediaQualitySettings) -> NativeMediaQualitySettings {
        NativeMediaQualitySettings(
            camera: normalizedCamera(settings.camera),
            screenShare: normalizedScreenShare(settings.screenShare)
        )
    }

    static func normalizedCamera(_ settings: NativeCameraQualitySettings) -> NativeCameraQualitySettings {
        var next = settings
        next.frameRate = bounded(settings.frameRate, minimum: 5, maximum: 60)
        next.maxBitrateKbps = bounded(settings.maxBitrateKbps, minimum: 100, maximum: 12_000)
        return next
    }

    static func normalizedScreenShare(_ settings: NativeScreenShareQualitySettings) -> NativeScreenShareQualitySettings {
        var next = settings
        next.frameRate = bounded(settings.frameRate, minimum: 1, maximum: 60)
        next.maxBitrateKbps = bounded(settings.maxBitrateKbps, minimum: 150, maximum: 15_000)
        return next
    }

    static func resolvedCamera(_ settings: NativeCameraQualitySettings) -> NativeResolvedCameraPublishSettings {
        let normalized = normalizedCamera(settings)
        return NativeResolvedCameraPublishSettings(
            width: normalized.resolution.width,
            height: normalized.resolution.height,
            frameRate: normalized.frameRate,
            maxBitrateBps: normalized.maxBitrateKbps * 1_000,
            contentHint: normalized.contentHint,
            degradationPreference: normalized.degradationPreference
        )
    }

    static func resolvedScreenShare(_ settings: NativeScreenShareQualitySettings) -> NativeResolvedScreenSharePublishSettings {
        let normalized = normalizedScreenShare(settings)
        let auto = defaultSettings.screenShare
        let matchesAutoVideoSettings = normalized.resolution == auto.resolution &&
            normalized.frameRate == auto.frameRate &&
            normalized.maxBitrateKbps == auto.maxBitrateKbps &&
            normalized.contentHint == auto.contentHint &&
            normalized.degradationPreference == auto.degradationPreference
        let conservativeIdeal = normalized.preset == .auto || matchesAutoVideoSettings
        let maxWidth = normalized.resolution.width
        let maxHeight = normalized.resolution.height
        return NativeResolvedScreenSharePublishSettings(
            idealWidth: conservativeIdeal ? min(1_920, maxWidth) : maxWidth,
            idealHeight: conservativeIdeal ? min(1_080, maxHeight) : maxHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            frameRate: normalized.frameRate,
            maxBitrateBps: normalized.maxBitrateKbps * 1_000,
            contentHint: normalized.contentHint,
            degradationPreference: normalized.degradationPreference,
            cursor: normalized.cursor,
            includeAudio: normalized.includeAudio
        )
    }

    static func baseVideoQuality(_ settings: NativeCameraQualitySettings) -> VideoQuality {
        let resolved = resolvedCamera(settings)
        return resolved.width <= 640 && resolved.maxBitrateBps <= 500_000 ? .low : .standard
    }

    static func bitrateLabel(kbps: Int) -> String {
        if kbps >= 1_000 {
            let whole = kbps / 1_000
            let remainder = (kbps % 1_000) / 100
            return remainder == 0 ? "\(whole) Mbps" : "\(whole).\(remainder) Mbps"
        }
        return "\(kbps) kbps"
    }

    private static func bounded(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(maximum, max(minimum, value))
    }
}

enum NativeMediaQualityPreferences {
    static let storageKey = "conclave:media-quality-settings:v1"

    static func load() -> NativeMediaQualitySettings {
        decode(UserDefaults.standard.string(forKey: storageKey))
    }

    static func save(_ settings: NativeMediaQualitySettings) {
        guard let value = encode(settings) else { return }
        UserDefaults.standard.set(value, forKey: storageKey)
    }

    static func decode(_ value: String?) -> NativeMediaQualitySettings {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(NativeMediaQualitySettings.self, from: data) else {
            return NativeMediaQualityPolicy.defaultSettings
        }
        return NativeMediaQualityPolicy.normalized(decoded)
    }

    static func encode(_ settings: NativeMediaQualitySettings) -> String? {
        let normalized = NativeMediaQualityPolicy.normalized(settings)
        guard let data = try? JSONEncoder().encode(normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
