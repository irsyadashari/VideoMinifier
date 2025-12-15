//
//  VideoLibraryViewModel.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//

import SwiftUI
import Photos
import Combine

class VideoLibraryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    
    @Published var assets: PHFetchResult<PHAsset> = PHFetchResult()
    @Published var hasPermission: Bool = false
    @Published var isLoading: Bool = false // NEW: Track loading state
    
    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        checkPermission()
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
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
        // 1. Set loading to true immediately
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        
        // 2. Perform fetch on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PHAsset.fetchAssets(with: options)
            
            // 3. Update UI on main thread
            DispatchQueue.main.async {
                self?.assets = result
                // Add a tiny delay so the user actually sees the refresh happen (optional but feels better)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.isLoading = false
                }
            }
        }
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        if let changeDetails = changeInstance.changeDetails(for: assets) {
            DispatchQueue.main.async {
                self.assets = changeDetails.fetchResultAfterChanges
            }
        }
    }
}
