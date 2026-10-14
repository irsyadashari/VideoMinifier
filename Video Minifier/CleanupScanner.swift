//
//  CleanupScanner.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//
//  Finds things worth deleting. Everything here runs off the main thread and
//  talks in local identifiers rather than PHAssets, so nothing non-Sendable
//  crosses a thread boundary.
//
//  PhotoKit does not expose Apple's own Duplicates album, so near-duplicates
//  are found with a difference hash: shrink to 9x8 greyscale, compare each
//  pixel with its right-hand neighbour, and keep the 64 resulting bits. Two
//  pictures of the same thing land within a few bits of each other.
//
//  Hashing is done a page at a time. The caller keeps every hash it has been
//  given and re-clusters the lot, so a duplicate whose twin sits in a later
//  page is still found.
//

import Photos
import UIKit
import Vision

nonisolated struct AssetHash: Sendable {
    let identifier: String
    let hash: UInt64
    let aspect: Double
}

nonisolated struct CleanupScanner {

    // MARK: - Duplicates

    static func hashes(for identifiers: [String],
                       isCancelled: @escaping @Sendable () -> Bool,
                       onProgress: @escaping @Sendable (Double) -> Void) -> [AssetHash] {
        let assets = fetchAssets(for: identifiers)
        var results: [AssetHash] = []
        results.reserveCapacity(identifiers.count)

        for (index, identifier) in identifiers.enumerated() {
            if isCancelled() { break }
            guard let asset = assets[identifier],
                  let image = loadImage(for: asset, maximumDimension: 72),
                  let cgImage = image.cgImage,
                  let hash = differenceHash(of: cgImage) else { continue }

            let aspect = asset.pixelHeight > 0
                ? Double(asset.pixelWidth) / Double(asset.pixelHeight)
                : 1
            results.append(AssetHash(identifier: identifier, hash: hash, aspect: aspect))

            if index % 10 == 0 {
                onProgress(Double(index) / Double(max(identifiers.count, 1)))
            }
        }
        return results
    }

    /// Greedy clustering. Even a few thousand hashes is only a handful of
    /// million 64-bit comparisons, so there is no need for anything cleverer.
    static func cluster(_ hashes: [AssetHash], tolerance: Int) -> [[String]] {
        var groups: [(hash: UInt64, aspect: Double, members: [String])] = []

        for entry in hashes {
            var matched = false
            for index in groups.indices {
                let sameShape = abs(groups[index].aspect - entry.aspect) < 0.02
                let distance = (groups[index].hash ^ entry.hash).nonzeroBitCount
                if sameShape, distance <= tolerance {
                    groups[index].members.append(entry.identifier)
                    matched = true
                    break
                }
            }
            if !matched {
                groups.append((entry.hash, entry.aspect, [entry.identifier]))
            }
        }

        return groups.filter { $0.members.count > 1 }.map(\.members)
    }

    // MARK: - QR codes

    static func qrIdentifiers(from identifiers: [String],
                              limit: Int,
                              isCancelled: @escaping @Sendable () -> Bool,
                              onProgress: @escaping @Sendable (Double) -> Void) -> [String] {
        let assets = fetchAssets(for: identifiers)

        // Screenshots first: a QR code someone kept is usually a screenshot.
        let screenshots = screenshotIdentifiers()
        let candidates = identifiers
            .filter { assets[$0]?.mediaType == .image }
            .sorted { lhs, rhs in
                screenshots.contains(lhs) && !screenshots.contains(rhs)
            }
            .prefix(limit)

        var found: [String] = []
        for (index, identifier) in candidates.enumerated() {
            if isCancelled() { break }
            guard let asset = assets[identifier],
                  let image = loadImage(for: asset, maximumDimension: 1_024),
                  let cgImage = image.cgImage else { continue }

            if containsQRCode(cgImage) {
                found.append(identifier)
            }

            if index % 5 == 0 {
                onProgress(Double(index) / Double(max(candidates.count, 1)))
            }
        }
        return found
    }

    // MARK: - Sizes

    /// Only ever called for the handful of assets actually on screen, which is
    /// why there is no bulk size pass any more.
    static func sizes(for identifiers: [String]) -> [String: Int64] {
        let assets = fetchAssets(for: identifiers)
        var sizes: [String: Int64] = [:]
        for identifier in identifiers {
            guard let asset = assets[identifier] else { continue }
            sizes[identifier] = asset.totalResourceByteCount
        }
        return sizes
    }

    // MARK: - Photo library

    private static func fetchAssets(for identifiers: [String]) -> [String: PHAsset] {
        guard !identifiers.isEmpty else { return [:] }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byIdentifier: [String: PHAsset] = [:]
        byIdentifier.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in
            byIdentifier[asset.localIdentifier] = asset
        }
        return byIdentifier
    }

    private static func screenshotIdentifiers() -> Set<String> {
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                             subtype: .smartAlbumScreenshots,
                                                             options: nil)
        guard let album = albums.firstObject else { return [] }

        var identifiers: Set<String> = []
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
            identifiers.insert(asset.localIdentifier)
        }
        return identifiers
    }

    /// Local copies only: a cleanup scan must not quietly pull the library
    /// down from iCloud.
    private static func loadImage(for asset: PHAsset, maximumDimension: CGFloat) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast

        var result: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: maximumDimension, height: maximumDimension),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            result = image
        }
        return result
    }

    // MARK: - Image analysis

    private static func differenceHash(of image: CGImage) -> UInt64? {
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] {
                    hash |= (1 << bit)
                }
                bit += 1
            }
        }
        return hash
    }

    private static func containsQRCode(_ image: CGImage) -> Bool {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .microQR]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return false
        }
        return !(request.results ?? []).isEmpty
    }
}
