//
//  QualityOption.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//

import AVKit

// 1. Define Quality Options mapped to AVAssetPresets
enum QualityOption: String, CaseIterable, Identifiable {
    case high = "High (1080p)"
    case medium = "Medium (720p)"
    case low = "Low (540p)"
    
    var id: String { self.rawValue }
    
    // Map enum to actual AVFoundation presets
    // Using explicit resolutions is often more reliable for compression goals than generic "HighQuality" presets
    var avPresetName: String {
        switch self {
        case .high: return AVAssetExportPreset1920x1080
        case .medium: return AVAssetExportPreset1280x720
        case .low: return AVAssetExportPreset960x540
        }
    }
}
