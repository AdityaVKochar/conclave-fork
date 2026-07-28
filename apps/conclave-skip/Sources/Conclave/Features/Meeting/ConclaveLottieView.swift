import SwiftUI
#if os(iOS)
import AVFoundation
import UIKit
#endif

/// The branded Conclave lockup animation used by the meeting-entry takeover.
/// Android uses LottieFiles' dotLottie player. iOS plays the same frames as a
/// hardware-decoded video because the source dotLottie contains 301 full-size
/// raster images; Lottie eagerly decodes them and exceeds the device's memory
/// limit during meeting startup.
struct ConclaveLottieView: View {
    var body: some View {
        #if SKIP
        ComposeView { _ in
            ConclaveLottieComposable()
        }
        #elseif os(iOS)
        ConclaveEntryVideoView()
        #else
        Color.black
        #endif
    }
}

#if os(iOS)
private struct ConclaveEntryVideoView: UIViewRepresentable {
    final class PlayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?

        func stop() {
            player?.pause()
            player?.removeAllItems()
            looper = nil
            player = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        // The source is landscape. Aspect-fill scales it to the full portrait
        // height, which crops the sides and makes the centered mark appear huge
        // and offset. The surrounding view is already black, so aspect-fit keeps
        // the complete animation centered without visible letterboxing.
        view.playerLayer.videoGravity = .resizeAspect

        guard let url = Bundle.module.url(
            forResource: "conclave-animation",
            withExtension: "mp4"
        ) else {
            return view
        }

        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        context.coordinator.player = player
        context.coordinator.looper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(url: url)
        )
        view.playerLayer.player = player
        player.playImmediately(atRate: 3.0)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard let player = context.coordinator.player,
              player.timeControlStatus != .playing else { return }
        player.playImmediately(atRate: 3.0)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player = nil
        coordinator.stop()
    }
}
#endif
