//
//  LargeVideosViewModel.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/13/26.
//

import SwiftUI
import Photos
import Combine

extension PHAsset {
    /// Byte size and original filename, read from the asset's underlying resources.
    var resourceInfo: (byteCount: Int64, originalFilename: String?) {
        var size: Int64 = 0
        var name: String?
        for resource in PHAssetResource.assetResources(for: self) {
            if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                size += fileSize
            }
            if name == nil {
                name = resource.originalFilename
            }
        }
        return (size, name)
    }

    var totalResourceByteCount: Int64 { resourceInfo.byteCount }
}

/// A video large enough to be worth suggesting for compression.
struct LargeVideo: Identifiable {
    let asset: PHAsset
    let byteCount: Int64
    let filename: String?

    var id: String { asset.localIdentifier }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var title: String { filename ?? "Video" }
}

/// Scans the Photos library for the videos eating the most storage.
class LargeVideosViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {

    @Published var videos: [LargeVideo] = []
    @Published var isScanning: Bool = false
    @Published var hasScanned: Bool = false
    @Published var hasPermission: Bool = false

    /// Videos below this size are not worth suggesting.
    private let minimumByteCount: Int64 = 100 * 1024 * 1024 // 100 MB
    private let maximumSuggestions = 5

    /// Kept so the change observer can tell when the video list changed.
    private var fetchResult: PHFetchResult<PHAsset>?

    /// A library change that arrived mid-scan; the results in flight are
    /// already stale, so another pass has to follow.
    private var pendingRescan = false

    var thresholdString: String {
        ByteCountFormatter.string(fromByteCount: minimumByteCount, countStyle: .file)
    }

    var totalByteCount: Int64 {
        videos.reduce(0) { $0 + $1.byteCount }
    }

    var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file)
    }

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        // The first scan is kicked off by the view appearing.
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// Called whenever the home screen appears. It always rescans: coming back
    /// from the compressor, the list on screen may name a video that has just
    /// been deleted, and tapping that row would open a dead asset.
    func refreshIfNeeded() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasPermission = (status == .authorized || status == .limited)
        if hasPermission {
            scan()
        }
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.hasPermission = (status == .authorized || status == .limited)
                if self?.hasPermission == true {
                    self?.scan()
                }
            }
        }
    }

    func scan() {
        guard hasPermission else { return }
        guard !isScanning else {
            pendingRescan = true
            return
        }
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            let result = PHAsset.fetchAssets(with: options)

            // Reading resources per asset is local metadata, but still slow
            // enough on big libraries to keep off the main thread.
            var found: [LargeVideo] = []
            result.enumerateObjects { asset, _, _ in
                let info = asset.resourceInfo
                if info.byteCount >= self.minimumByteCount {
                    found.append(LargeVideo(asset: asset,
                                            byteCount: info.byteCount,
                                            filename: info.originalFilename))
                }
            }

            let largest = found
                .sorted { $0.byteCount > $1.byteCount }
                .prefix(self.maximumSuggestions)

            DispatchQueue.main.async {
                self.fetchResult = result
                self.videos = Array(largest)
                self.isScanning = false
                self.hasScanned = true

                if self.pendingRescan {
                    self.pendingRescan = false
                    self.scan()
                }
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Hop to main first so fetchResult is only touched on one thread.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let result = self.fetchResult else { return }
            if changeInstance.changeDetails(for: result) != nil {
                self.scan()
            }
        }
    }
}
