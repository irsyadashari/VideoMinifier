//
//  CompressionActivityAttributes.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/13/26.
//
//  Compiled into both the app and the Live Activity widget, so the two
//  agree on the shape of the activity's state.
//

import ActivityKit
import Foundation

struct CompressionActivityAttributes: ActivityAttributes {

    enum Phase: String, Codable, Hashable {
        case preparing
        case downloading
        case compressing
        case paused
        case done
        case failed

        var symbolName: String {
            switch self {
            case .preparing: return "hourglass"
            case .downloading: return "icloud.and.arrow.down"
            case .compressing: return "arrow.down.circle"
            case .paused: return "pause.circle"
            case .done: return "checkmark.circle"
            case .failed: return "exclamationmark.triangle"
            }
        }
    }

    public struct ContentState: Codable, Hashable {
        var phase: Phase
        /// 0...1 within the current phase.
        var progress: Double
        /// Short label, e.g. "Downloading from iCloud".
        var statusText: String
        /// e.g. "2:05 left"; nil when unknown.
        var etaText: String?

        var isFinished: Bool { phase == .done || phase == .failed }
    }

    /// Fixed for the life of the activity.
    var videoName: String
}
