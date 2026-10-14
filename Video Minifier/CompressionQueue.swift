//
//  CompressionQueue.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//
//  Compression lives here rather than in a screen, so it keeps running while
//  the user moves around the app. Jobs run one at a time on purpose: the video
//  encoder is a single piece of hardware, so two at once would just queue up
//  behind each other while using twice the memory.
//
//  Leaving the app is still bounded by iOS, which will not run the encoder for
//  a suspended app. The queue handles that the same way the single-video
//  screen does: it banks a checkpoint and carries on when the app is back.
//

import AVFoundation
import Combine
import Photos
import SwiftUI
import UIKit

@MainActor
final class CompressionQueue: ObservableObject {

    enum JobState: Equatable {
        case waiting
        case preparing(Double)
        case compressing(Double)
        case paused(Double)
        case saving
        case finished(savedBytes: Int64)
        case skipped(String)
        case failed(String)

        /// How far through this job we are, 0...1.
        var fraction: Double {
            switch self {
            case .waiting: return 0
            // The iCloud fetch is counted as the first tenth of the job
            case .preparing(let value): return value * 0.1
            case .compressing(let value): return 0.1 + value * 0.9
            case .paused(let value): return value
            case .saving: return 1
            case .finished, .skipped, .failed: return 1
            }
        }

        var isFinished: Bool {
            switch self {
            case .finished, .skipped, .failed: return true
            default: return false
            }
        }

        var label: String {
            switch self {
            case .waiting: return "Waiting"
            case .preparing: return "Downloading from iCloud"
            case .compressing: return "Compressing"
            case .paused: return "Paused — reopen to continue"
            case .saving: return "Saving"
            case .finished(let saved):
                return "Saved \(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file))"
            case .skipped(let reason): return reason
            case .failed(let message): return message
            }
        }
    }

    struct Job: Identifiable {
        let id: String
        let asset: PHAsset
        let name: String
        let originalBytes: Int64
        var state: JobState = .waiting
    }

    enum OriginalPolicy: String, CaseIterable, Identifiable {
        case keep = "Keep originals"
        case replace = "Delete originals"

        var id: String { rawValue }

        var explanation: String {
            switch self {
            case .keep: return "The compressed copies are added alongside the originals."
            case .replace: return "Originals go to Recently Deleted once every copy is saved. iOS asks you to confirm, once, at the end."
            }
        }
    }

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published var quality: QualityOption = .medium
    @Published var policy: OriginalPolicy = .keep
    @Published var lastSummary: String?
    /// Drives the queue screen, which is presented from the root so it can be
    /// reopened from anywhere once it has been closed.
    @Published var isShowingQueue = false

    private let activity = CompressionActivityManager()
    private var runTask: Task<Void, Never>?
    private var stopSignal: VideoCompressor.StopSignal?
    private var graceTask: Task<Void, Never>?
    private var foregroundWaiters: [CheckedContinuation<Void, Never>] = []
    private var assetRequestID: PHImageRequestID?
    private var originalsToDelete: [PHAsset] = []

    init() {
        observeLifecycle()
    }

    // MARK: - Derived state

    var finishedCount: Int { jobs.filter { $0.state.isFinished }.count }

    var activeJob: Job? {
        jobs.first { !$0.state.isFinished && $0.state != .waiting }
    }

    var overallFraction: Double {
        guard !jobs.isEmpty else { return 0 }
        return jobs.reduce(0) { $0 + $1.state.fraction } / Double(jobs.count)
    }

    var totalSaved: Int64 {
        jobs.reduce(into: Int64(0)) { total, job in
            if case .finished(let saved) = job.state { total += saved }
        }
    }

    var statusLine: String {
        if isPaused { return "Paused — open the app to continue" }
        guard isRunning else { return "" }
        return "Compressing \(min(finishedCount + 1, jobs.count)) of \(jobs.count)"
    }

    // MARK: - Building the queue

    func enqueue(_ items: [LargeVideo]) {
        for item in items where !jobs.contains(where: { $0.id == item.id }) {
            jobs.append(Job(id: item.id,
                            asset: item.asset,
                            name: item.title,
                            originalBytes: item.byteCount))
        }
    }

    func removeFinished() {
        jobs.removeAll { $0.state.isFinished }
        if jobs.isEmpty { lastSummary = nil }
    }

    func remove(_ job: Job) {
        guard job.state == .waiting || job.state.isFinished else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func cancelAll() {
        runTask?.cancel()
        runTask = nil
        stopSignal?.requestStop()
        cancelAssetRequest()
        resumeForegroundWaiters()

        for index in jobs.indices where !jobs[index].state.isFinished {
            jobs[index].state = .skipped("Cancelled")
        }
        isRunning = false
        isPaused = false
        activity.cancel()
    }

    // MARK: - Running

    func start() {
        guard !isRunning, jobs.contains(where: { $0.state == .waiting }) else { return }

        isRunning = true
        lastSummary = nil
        originalsToDelete = []

        activity.requestNotificationPermissionIfNeeded()
        activity.start(videoName: "\(jobs.count) video\(jobs.count == 1 ? "" : "s")")
        activity.beginBackgroundTask(onExpiration: requestPause)

        runTask = Task { [weak self] in
            guard let queue = self else { return }
            await queue.drain()
        }
    }

    private func drain() async {
        // Picks up anything added while already running
        while let next = jobs.first(where: { $0.state == .waiting })?.id {
            if Task.isCancelled { break }
            await process(jobID: next)
        }

        await deleteOriginalsIfAsked()

        isRunning = false
        isPaused = false

        let saved = ByteCountFormatter.string(fromByteCount: totalSaved, countStyle: .file)
        let done = jobs.filter { if case .finished = $0.state { return true } else { return false } }.count
        lastSummary = done == 0
            ? "Nothing was compressed."
            : "Compressed \(done) video\(done == 1 ? "" : "s") — saved \(saved)."

        activity.finish(savedText: lastSummary ?? "")
    }

    private func process(jobID: String) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let asset = jobs[index].asset

        update(jobID, to: .preparing(0))

        do {
            let avAsset = try await loadAsset(for: asset, jobID: jobID)
            try Task.checkCancellation()

            update(jobID, to: .compressing(0))
            let outputURL = try await compress(asset: avAsset, jobID: jobID)

            // Nothing to gain from a copy that came out bigger, and there is
            // nobody watching to ask, so it is dropped.
            let compressedBytes = fileSize(at: outputURL)
            guard compressedBytes > 0, compressedBytes < jobs[index].originalBytes else {
                try? FileManager.default.removeItem(at: outputURL)
                update(jobID, to: .skipped("Skipped — wouldn't have been smaller"))
                return
            }

            update(jobID, to: .saving)
            try await saveToLibrary(outputURL)
            try? FileManager.default.removeItem(at: outputURL)

            if policy == .replace {
                originalsToDelete.append(asset)
            }
            update(jobID, to: .finished(savedBytes: jobs[index].originalBytes - compressedBytes))
        } catch is CancellationError {
            // A pause cancels the iCloud fetch, which arrives here as a
            // cancellation. That is not the user giving up: hold, then put the
            // job back in line. Downloads have no checkpoint, but iOS keeps
            // what it already pulled down.
            if isPaused {
                await holdUntilForeground(jobID: jobID)
                update(jobID, to: .waiting)
            } else {
                update(jobID, to: .skipped("Cancelled"))
            }
        } catch {
            update(jobID, to: .failed(error.localizedDescription))
        }
    }

    /// Fetches the full-quality original, downloading from iCloud if needed.
    private func loadAsset(for asset: PHAsset, jobID: String) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.progressHandler = { [weak self] progress, _, _, _ in
                guard let queue = self else { return }
                Task { @MainActor in
                    queue.update(jobID, to: .preparing(progress))
                }
            }

            assetRequestID = PHImageManager.default().requestAVAsset(forVideo: asset,
                                                                     options: options) { avAsset, _, info in
                Task { @MainActor in self.assetRequestID = nil }

                if let avAsset = avAsset {
                    continuation.resume(returning: avAsset)
                } else if (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.resume(throwing: CancellationError())
                } else {
                    let error = (info?[PHImageErrorKey] as? Error)
                        ?? VideoCompressorError.failed("Could not load the video.")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The same checkpoint-and-resume loop the single-video screen uses.
    private func compress(asset: AVAsset, jobID: String) async throws -> URL {
        var segments: [URL] = []
        var resumeAt = CMTime.zero
        let finalURL = temporaryURL(prefix: "compressed")

        while true {
            try Task.checkCancellation()

            let signal = VideoCompressor.StopSignal()
            stopSignal = signal
            let segmentURL = temporaryURL(prefix: "segment")

            let outcome = try await VideoCompressor.compress(asset: asset,
                                                            to: segmentURL,
                                                            quality: quality,
                                                            from: resumeAt,
                                                            stopSignal: signal) { [weak self] fraction in
                guard let queue = self else { return }
                Task { @MainActor in
                    queue.update(jobID, to: .compressing(fraction))
                }
            }

            switch outcome {
            case .completed:
                segments.append(segmentURL)
                try await VideoCompressor.join(segments: segments, to: finalURL)
                segments.forEach { try? FileManager.default.removeItem(at: $0) }
                return finalURL

            case .interrupted(let resumeTime, let wroteSegment):
                if wroteSegment {
                    segments.append(segmentURL)
                    guard resumeTime > resumeAt else {
                        throw VideoCompressorError.failed("Compression could not make progress.")
                    }
                    resumeAt = resumeTime
                } else {
                    try? FileManager.default.removeItem(at: segmentURL)
                }

                await holdUntilForeground(jobID: jobID)
                try Task.checkCancellation()
            }
        }
    }

    private func saveToLibrary(_ url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    /// One prompt at the end rather than one per video.
    private func deleteOriginalsIfAsked() async {
        guard policy == .replace, !originalsToDelete.isEmpty else { return }
        let assets = originalsToDelete
        originalsToDelete = []

        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    // MARK: - Pausing around the background

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            guard let queue = self else { return }
            Task { @MainActor in queue.handleEnteredBackground() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            guard let queue = self else { return }
            Task { @MainActor in queue.handleWillEnterForeground() }
        }
    }

    private func handleEnteredBackground() {
        guard isRunning, !isPaused else { return }

        graceTask?.cancel()
        graceTask = Task { [weak self] in
            // Spend the runtime iOS grants, then checkpoint while there is
            // still time to close the file cleanly.
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.requestPause()
        }
    }

    private func handleWillEnterForeground() {
        graceTask?.cancel()
        graceTask = nil
        resumeForegroundWaiters()
    }

    private func requestPause() {
        guard isRunning, !isPaused else { return }

        graceTask?.cancel()
        graceTask = nil
        isPaused = true
        stopSignal?.requestStop()
        cancelAssetRequest()
        activity.pause(progress: overallFraction)
    }

    private func holdUntilForeground(jobID: String) async {
        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[index].state = .paused(jobs[index].state.fraction)
        }

        if UIApplication.shared.applicationState != .active {
            await withCheckedContinuation { continuation in
                foregroundWaiters.append(continuation)
            }
        }

        isPaused = false
        activity.beginBackgroundTask(onExpiration: requestPause)
        activity.update(phase: .compressing,
                        progress: overallFraction,
                        statusText: statusLine,
                        etaText: nil,
                        force: true)
    }

    private func resumeForegroundWaiters() {
        let waiting = foregroundWaiters
        foregroundWaiters = []
        waiting.forEach { $0.resume() }
    }

    // MARK: - Helpers

    private func update(_ jobID: String, to state: JobState) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].state = state

        activity.update(phase: isPaused ? .paused : .compressing,
                        progress: overallFraction,
                        statusText: statusLine,
                        etaText: nil)
    }

    private func cancelAssetRequest() {
        if let id = assetRequestID {
            PHImageManager.default().cancelImageRequest(id)
            assetRequestID = nil
        }
    }

    private func temporaryURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).mp4")
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int64) ?? 0
    }
}
