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

nonisolated struct PageFindings: Sendable {
    var hashes: [AssetHash] = []
    var qrIdentifiers: [String] = []
}

nonisolated struct CleanupScanner {

    // MARK: - One page of the library
    
    /// Hashes every item and looks for a QR code in the photos, from a single
    /// image load each. Two separate passes would double the I/O, which is the
    /// slow part.
    static func scanPage(identifiers: [String],
                         isCancelled: @escaping @Sendable () -> Bool,
                         onProgress: @escaping @Sendable (Double) -> Void) -> PageFindings {
        let assets = fetchAssets(for: identifiers)
        var findings = PageFindings()
        findings.hashes.reserveCapacity(identifiers.count)
        
        for (index, identifier) in identifiers.enumerated() {
            if isCancelled() { break }
            guard let asset = assets[identifier],
                  let image = loadImage(for: asset, maximumDimension: 1_024),
                  let cgImage = image.cgImage else { continue }
            
            if let hash = differenceHash(of: cgImage) {
                let aspect = asset.pixelHeight > 0
                    ? Double(asset.pixelWidth) / Double(asset.pixelHeight)
                    : 1
                findings.hashes.append(AssetHash(identifier: identifier, hash: hash, aspect: aspect))
            }
            
            if asset.mediaType == .image, containsQRCode(cgImage) {
                findings.qrIdentifiers.append(identifier)
            }
            
            onProgress(Double(index + 1) / Double(max(identifiers.count, 1)))
        }
        return findings
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
