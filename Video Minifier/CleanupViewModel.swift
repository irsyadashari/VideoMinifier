//
//  CleanupViewModel.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import Combine
import Photos
import SwiftUI

struct CleanupItem: Identifiable {
    let asset: PHAsset
    let byteCount: Int64

    var id: String { asset.localIdentifier }
    var isVideo: Bool { asset.mediaType == .video }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var dateString: String {
        guard let date = asset.creationDate else { return "" }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct DuplicateGroup: Identifiable {
    let id: String
    /// Biggest first: that is the copy worth keeping.
    var items: [CleanupItem]
}

/// Scans the library for things worth deleting, a page at a time, and deletes
/// what is picked.
class CleanupViewModel: ObservableObject {

    @Published var hasPermission = false
    /// The first pass, which the screen blocks on.
    @Published var isScanning = false
    /// Later pages, pulled in as the user reaches the bottom of the list.
    @Published var isLoadingMore = false
    @Published var hasScanned = false
    @Published var stageText = ""
    @Published var progress: Double = 0

    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var qrItems: [CleanupItem] = []

    @Published var selection: Set<String> = []
    /// How many pictures the user has told us to leave alone.
    @Published private(set) var ignoredCount = 0
    @Published var errorMessage: String?

    @Published private(set) var scannedCount = 0
    @Published private(set) var libraryCount = 0

    private let pageSize = 400
    private let qrScanLimit = 400
    /// Bits of difference still considered the same picture.
    private let duplicateTolerance = 5

    /// Unticking something is a decision to keep it, and that decision has to
    /// outlive the scan — otherwise every rescan offers it up again.
    private var ignored: Set<String> = []
    private let ignoredKey = "cleanup.keptAssetIdentifiers"

    private var allIdentifiers: [String] = []
    private var hashes: [AssetHash] = []
    private var sizeCache: [String: Int64] = [:]
    /// Members already given their default tick, so a rebuild does not undo
    /// what the user has since changed.
    private var defaulted: Set<String> = []

    private var scanTask: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    init() {
        ignored = Set(UserDefaults.standard.stringArray(forKey: ignoredKey) ?? [])
        ignoredCount = ignored.count
    }

    var canLoadMore: Bool { scannedCount < libraryCount }

    var foundAnything: Bool {
        !duplicateGroups.isEmpty || !qrItems.isEmpty
    }

    private var allItems: [CleanupItem] {
        duplicateGroups.flatMap(\.items) + qrItems
    }

    var selectedCount: Int {
        Set(allItems.filter { selection.contains($0.id) }.map(\.id)).count
    }

    var selectedByteCount: Int64 {
        var seen: Set<String> = []
        return allItems.reduce(into: Int64(0)) { total, item in
            guard selection.contains(item.id), seen.insert(item.id).inserted else { return }
            total += item.byteCount
        }
    }

    var selectedSizeString: String {
        ByteCountFormatter.string(fromByteCount: selectedByteCount, countStyle: .file)
    }

    // MARK: - Permission

    func refreshPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasPermission = (status == .authorized || status == .limited)
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.hasPermission = (status == .authorized || status == .limited)
            }
        }
    }

    // MARK: - Selection

    func isSelected(_ item: CleanupItem) -> Bool {
        selection.contains(item.id)
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
            // "I want to keep this": stay out of later scans
            ignored.insert(item.id)
        } else {
            selection.insert(item.id)
            ignored.remove(item.id)
        }
        persistIgnored()
    }

    /// Brings everything the user chose to keep back into play.
    func resetIgnored() {
        ignored = []
        persistIgnored()
    }

    func clearSelection() {
        selection.removeAll()
    }

    private func persistIgnored() {
        UserDefaults.standard.set(Array(ignored), forKey: ignoredKey)
        ignoredCount = ignored.count
    }

    // MARK: - Scanning

    func startScan() {
        guard hasPermission, !isScanning else { return }

        scanTask?.cancel()
        cancelFlag.cancel()
        cancelFlag = CancelFlag()

        duplicateGroups = []
        qrItems = []
        selection = []
        defaulted = []
        hashes = []
        sizeCache = [:]
        errorMessage = nil
        progress = 0
        scannedCount = 0

        allIdentifiers = fetchAllIdentifiers()
        libraryCount = allIdentifiers.count
        isScanning = true
        stageText = "Looking for QR codes"

        let flag = cancelFlag
        scanTask = Task { [weak self] in
            guard let model = self else { return }

            await model.runQRPass(flag: flag)
            guard !flag.isCancelled else { return }

            model.stageText = "Looking for duplicates"
            _ = await model.scanNextPage(flag: flag)

            guard !flag.isCancelled else { return }
            model.isScanning = false
            model.hasScanned = true
        }
    }

    func cancelScan() {
        cancelFlag.cancel()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        isLoadingMore = false
    }

    /// Called when the bottom of the list comes into view.
    func loadMoreIfNeeded() {
        guard hasPermission, !isScanning, !isLoadingMore, canLoadMore else { return }

        isLoadingMore = true
        let flag = cancelFlag

        scanTask = Task { [weak self] in
            guard let model = self else { return }

            // A page that turns up nothing would leave the trigger row sitting
            // at the bottom with nothing new to show, so keep going for a few.
            for _ in 0..<3 {
                if flag.isCancelled || !model.canLoadMore { break }
                let added = await model.scanNextPage(flag: flag)
                if added > 0 { break }
            }
            model.isLoadingMore = false
        }
    }

    private func scanNextPage(flag: CancelFlag) async -> Int {
        let start = scannedCount
        guard start < allIdentifiers.count else { return 0 }

        let end = min(start + pageSize, allIdentifiers.count)
        let page = Array(allIdentifiers[start..<end])

        let newHashes = await Self.onBackground {
            CleanupScanner.hashes(for: page,
                                  isCancelled: { flag.isCancelled },
                                  onProgress: { _ in })
        }
        guard !flag.isCancelled else { return 0 }

        scannedCount = end
        hashes.append(contentsOf: newHashes)

        let before = duplicateGroups.count
        await rebuildDuplicateGroups(flag: flag)
        return duplicateGroups.count - before
    }

    private func rebuildDuplicateGroups(flag: CancelFlag) async {
        let snapshot = hashes
        let tolerance = duplicateTolerance
        let kept = ignored

        let groups = await Self.onBackground {
            CleanupScanner.cluster(snapshot, tolerance: tolerance)
        }
        guard !flag.isCancelled else { return }

        // A set with only one copy left is no longer a duplicate
        let usable = groups.map { $0.filter { !kept.contains($0) } }.filter { $0.count > 1 }
        let items = await makeItems(for: usable.flatMap { $0 })

        duplicateGroups = usable.compactMap { identifiers in
            let members = identifiers.compactMap { items[$0] }.sorted { $0.byteCount > $1.byteCount }
            guard members.count > 1, let first = members.first else { return nil }
            return DuplicateGroup(id: first.id, items: members)
        }

        applyDefaultTicks()
    }

    private func runQRPass(flag: CancelFlag) async {
        let identifiers = allIdentifiers
        let limit = qrScanLimit

        let found = await Self.onBackground {
            CleanupScanner.qrIdentifiers(from: identifiers,
                                         limit: limit,
                                         isCancelled: { flag.isCancelled },
                                         onProgress: { _ in })
        }
        guard !flag.isCancelled else { return }

        let kept = ignored
        let usable = found.filter { !kept.contains($0) }
        let items = await makeItems(for: usable)
        qrItems = usable.compactMap { items[$0] }
    }

    /// Ticks the redundant copies of each set, leaving anything the user has
    /// already had an opinion about alone.
    private func applyDefaultTicks() {
        for group in duplicateGroups {
            for item in group.items.dropFirst() where !defaulted.contains(item.id) {
                selection.insert(item.id)
                defaulted.insert(item.id)
            }
            if let keeper = group.items.first {
                defaulted.insert(keeper.id)
            }
        }
    }

    // MARK: - Items

    private func makeItems(for identifiers: [String]) async -> [String: CleanupItem] {
        guard !identifiers.isEmpty else { return [:] }

        let missing = identifiers.filter { sizeCache[$0] == nil }
        if !missing.isEmpty {
            let sizes = await Self.onBackground { CleanupScanner.sizes(for: missing) }
            sizeCache.merge(sizes) { _, new in new }
        }

        let assets = fetchAssets(for: identifiers)
        var items: [String: CleanupItem] = [:]
        for identifier in identifiers {
            guard let asset = assets[identifier] else { continue }
            items[identifier] = CleanupItem(asset: asset, byteCount: sizeCache[identifier] ?? 0)
        }
        return items
    }

    private func fetchAllIdentifiers() -> [String] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var identifiers: [String] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            identifiers.append(asset.localIdentifier)
        }
        return identifiers
    }

    private func fetchAssets(for identifiers: [String]) -> [String: PHAsset] {
        guard !identifiers.isEmpty else { return [:] }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var byIdentifier: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in
            byIdentifier[asset.localIdentifier] = asset
        }
        return byIdentifier
    }

    private nonisolated static func onBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    // MARK: - Deleting

    /// iOS puts up its own confirmation before anything leaves the library.
    func deleteSelected() async {
        let assets = allItems.filter { selection.contains($0.id) }.map(\.asset)
        guard !assets.isEmpty else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            removeDeletedFromLists()
        } catch {
            // A user who taps Cancel in the system prompt is not an error
            if (error as NSError).code != 3072 {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeDeletedFromLists() {
        let deleted = selection
        ignored.subtract(deleted)
        persistIgnored()

        hashes.removeAll { deleted.contains($0.identifier) }

        duplicateGroups = duplicateGroups.compactMap { group in
            let remaining = group.items.filter { !deleted.contains($0.id) }
            guard remaining.count > 1, let first = remaining.first else { return nil }
            return DuplicateGroup(id: first.id, items: remaining)
        }
        qrItems.removeAll { deleted.contains($0.id) }
        selection = []
    }
}

/// Shared between the main actor and the scan running on a background queue.
nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}
