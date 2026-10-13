//
//  PreviewPlayer.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/13/26.
//

import AVKit
import SwiftUI

/// SwiftUI's `VideoPlayer` gives no access to the player controller, which by
/// default runs Live Text / subject analysis on video frames and publishes Now
/// Playing info. Neither is useful for a throwaway preview, and both cost work.
struct PreviewPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsVideoFrameAnalysis = false
        controller.updatesNowPlayingInfoCenter = false
        controller.videoGravity = .resizeAspect
        controller.entersFullScreenWhenPlaybackBegins = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

enum PreviewAudioSession {
    /// An app's default audio category is `soloAmbient`, which obeys the
    /// Ring/Silent switch — so a video plays silently whenever the phone is on
    /// silent. `.playback` is the category for watching video with sound.
    ///
    /// The session is only set up here, never activated: AVPlayer activates it
    /// itself when playback starts, so whatever the user was listening to is
    /// not interrupted unless they actually press play.
    static func configureForPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension AVPlayerItem {
    /// Caps what the preview is allowed to pull down and decode. Checking you
    /// picked the right video does not need 4K, and on an iCloud video every
    /// extra pixel is downloaded over the network.
    func applyPreviewQualityLimits() {
        // Roughly 480p is plenty on a phone-sized preview pane
        preferredMaximumResolution = CGSize(width: 854, height: 480)
        preferredPeakBitRate = 2_000_000

        // Tighter again on cellular or a personal hotspot
        preferredMaximumResolutionForExpensiveNetworks = CGSize(width: 640, height: 360)
        preferredPeakBitRateForExpensiveNetworks = 800_000
    }
}
