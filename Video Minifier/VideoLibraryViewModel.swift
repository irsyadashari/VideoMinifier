//
//  VideoLibraryViewModel.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//

import SwiftUI
import Photos
import Combine

// MARK: - 1. The ViewModel (Logic Layer)
// Handles fetching assets and permissions so the View stays clean.
class VideoLibraryViewModel: ObservableObject {
    @Published var assets: PHFetchResult<PHAsset> = PHFetchResult()
    @Published var hasPermission: Bool = false
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            self.hasPermission = true
            self.fetchVideos()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self?.hasPermission = true
                        self?.fetchVideos()
                    }
                }
            }
        default:
            self.hasPermission = false
        }
    }
    
    func fetchVideos() {
        let options = PHFetchOptions()
        // Sort by newest first
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Filter specifically for Videos
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        
        DispatchQueue.main.async {
            self.assets = PHAsset.fetchAssets(with: options)
        }
    }
}
