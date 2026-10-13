//
//  CompressorView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//

import SwiftUI
import PhotosUI
import AVKit

/// Where the video being compressed comes from.
enum VideoSource {
    case photo(PHAsset)
    case file(URL)
}

struct CompressorView: View {
    let source: VideoSource

    init(asset: PHAsset) { self.source = .photo(asset) }
    init(fileURL: URL) { self.source = .file(fileURL) }

    // Security-scoped access for files picked from the Files app
    @State private var isAccessingScopedResource = false
    @State private var showingFileMover = false

    // UI State
    @State private var player: AVPlayer?
    @State private var selectedQuality: QualityOption = .medium
    @State private var isCompressing = false
    @State private var progress: Float = 0.0

    // iCloud State
    // Non-nil only while Photos is actually pulling bytes down from iCloud.
    @State private var previewDownloadProgress: Double?
    @State private var previewDownloadETA: String?
    @State private var previewStartTime: Date?
    @State private var hasRequestedPreview = false
    /// The player shows black until its item is ready; this gates the placeholder.
    @State private var isPlayerReady = false
    @State private var playerGeneration = 0

    // Full-quality download that happens just before the export
    @State private var isPreparingAsset = false
    @State private var prepareProgress: Double = 0.0
    @State private var prepareETA: String = ""
    @State private var prepareStartTime: Date?

    // ETA Calculation State
    @State private var timeRemainingString: String = "Calculating..."
    @State private var startTime: Date?
    
    // File Size State
    // Read once off the main thread; Photos metadata lookups are not cheap.
    @State private var originalBytes: Int64 = 0
    @State private var displayName: String = "Video"
    @State private var originalSizeString: String = "Calculating..."
    @State private var compressedSizeString: String = ""
    @State private var savedSizeString: String = ""
    @State private var sizeIncreased = false
    
    // Background / Live Activity
    @StateObject private var activityManager = CompressionActivityManager()
    @State private var exportTask: Task<Void, Never>?
    @State private var assetRequestID: PHImageRequestID?
    /// Set while the export is holding for the app to come back to the front.
    @State private var isPaused = false
    @State private var stopSignal: VideoCompressor.StopSignal?
    /// Finalised pieces of the current compression, joined at the end.
    @State private var segmentURLs: [URL] = []
    @State private var resumeAt: CMTime = .zero
    /// Overall progress when the current sitting began, for an honest ETA.
    @State private var progressAtSessionStart: Float = 0
    @State private var backgroundGraceTask: Task<Void, Never>?
    @State private var foregroundWaiters: [CheckedContinuation<Void, Never>] = []

    // Alerts & Modals
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSuccessModal = false
    @State private var compressedVideoURL: URL?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // MARK: - Main Content Layer
            VStack(spacing: 16) {
                
                // 1. Video Preview Player
                ZStack {
                    if let player = player {
                        // Deliberately not auto-playing: on an iCloud video that
                        // would stream the whole thing just to glance at it.
                        PreviewPlayer(player: player)
                    }

                    if isCompressing {
                        // Player released for the encode; the overlay covers this
                        Color.black
                    } else if player == nil || !isPlayerReady {
                        // A player that exists but isn't ready renders pure
                        // black, so keep the placeholder on top until then.
                        previewPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(12)
                .padding([.horizontal, .top])
                
                // Show Original File Size
                VStack(spacing: 4) {
                    Text("Original Size: \(originalSizeString)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if case .photo = source {
                        // Set expectations: the player shows a cheap proxy copy
                        Text("Preview is a lower-quality copy. Compression uses the original.")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // 2. Bottom Controls
                VStack(spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose Compression Quality")
                            .font(.headline)
                            .padding(.leading, 4)
                        
                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(QualityOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Compress Button
                    Button(action: startCompression) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Start Compressing")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(player == nil || isCompressing)
                    .opacity((player == nil || isCompressing) ? 0.6 : 1.0)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            
            // MARK: - Blocking Loading Overlay
            if isCompressing {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack(spacing: 24) {
                            Text("\(Int(overlayProgress * 100))%")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            VStack(spacing: 8) {
                                ProgressView(value: overlayProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                    .scaleEffect(x: 1, y: 2, anchor: .center)

                                HStack {
                                    Text(overlayStatus)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text(isPreparingAsset ? prepareETA : timeRemainingString)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 40)
                            
                            Text("You can leave the app — progress shows on your lock screen, and nothing is lost: it continues from where it stopped when you come back.")
                                .font(.footnote)
                                .foregroundColor(.gray.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    )
                    .onTapGesture { }
            }
            
            // MARK: - Success Modal
            if showingSuccessModal {
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack(spacing: 24) {
                            Image(systemName: sizeIncreased ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(sizeIncreased ? .orange : .green)
                            
                            Text(sizeIncreased ? "Size Increased" : "Compression Complete!")
                                .font(.title2)
                                .bold()
                            
                            HStack(spacing: 40) {
                                VStack {
                                    Text("Before")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(originalSizeString)
                                        .font(.headline)
                                }
                                Image(systemName: "arrow.right").foregroundColor(.gray)
                                VStack {
                                    Text("After")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(compressedSizeString)
                                        .font(.headline)
                                        .foregroundColor(sizeIncreased ? .red : .primary)
                                }
                            }
                            
                            if sizeIncreased {
                                VStack(spacing: 4) {
                                    Text("Size increased by \(savedSizeString)")
                                        .font(.headline).foregroundColor(.red)
                                    Text("Original video was already highly compressed.")
                                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                                }
                                .padding(8).background(Color.red.opacity(0.1)).cornerRadius(8)
                            } else {
                                Text("You saved \(savedSizeString)!")
                                    .font(.headline).foregroundColor(.green)
                                    .padding(8).background(Color.green.opacity(0.1)).cornerRadius(8)
                            }
                            
                            VStack(spacing: 12) {
                                if case .photo = source {
                                    if !sizeIncreased {
                                        Button(action: saveCompressedAndDeleteOriginal) {
                                            Text("Delete Original & Save New")
                                                .bold().frame(maxWidth: .infinity).padding()
                                                .background(Color.red).foregroundColor(.white).cornerRadius(10)
                                        }
                                    }
                                    // One closure, not a ternary of two: picking
                                    // between closures drops main-actor isolation.
                                    Button(action: {
                                        if sizeIncreased {
                                            dismiss()
                                        } else {
                                            saveCompressedOnly()
                                        }
                                    }) {
                                        Text(sizeIncreased ? "Cancel & Discard" : "Keep Original & Save New")
                                            .frame(maxWidth: .infinity).padding()
                                            .background(Color.primary.opacity(0.05)).foregroundColor(.primary).cornerRadius(10)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                                    }
                                } else {
                                    // Video picked from Files: original is never modified
                                    if !sizeIncreased {
                                        Button(action: { showingFileMover = true }) {
                                            Text("Save to Files")
                                                .bold().frame(maxWidth: .infinity).padding()
                                                .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                                        }
                                        Button(action: saveCompressedOnly) {
                                            Text("Save to Photos")
                                                .frame(maxWidth: .infinity).padding()
                                                .background(Color.primary.opacity(0.05)).foregroundColor(.primary).cornerRadius(10)
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                                        }
                                    }
                                    Button(action: { dismiss() }) {
                                        Text("Discard")
                                            .frame(maxWidth: .infinity).padding()
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                            .padding(24)
                            .background(Color(.systemBackground))
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
                            .padding(.horizontal, 40)
                    )
            }
        }
        .navigationTitle("Preview & Compress")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isCompressing || showingSuccessModal)
        
        // MARK: - Toolbar Implementation
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Deleting is only offered for Photos library videos
                if case .photo = source {
                    Button(action: deleteVideoWithoutCompressing) {
                        Image(systemName: "trash")
                            // An explicit tint would otherwise hide the disabled state
                            .foregroundColor(isDeleteDisabled ? .gray : .red)
                    }
                    .disabled(isDeleteDisabled)
                    // Conditional toolbar content can keep a stale .disabled,
                    // so block the hit directly as well.
                    .allowsHitTesting(!isDeleteDisabled)
                    .id(isDeleteDisabled)
                }
            }
        }

        .onAppear {
            PreviewAudioSession.configureForPlayback()
            loadVideoPlayer()
            loadMetadata()
        }
        // Polling beats a KVO observer here: it runs on the main actor, needs
        // no stored subscription, and stops as soon as the frame is available.
        .task(id: playerGeneration) {
            guard playerGeneration > 0, let item = player?.currentItem else { return }
            isPlayerReady = false

            while !Task.isCancelled {
                switch item.status {
                case .readyToPlay:
                    isPlayerReady = true
                    return
                case .failed:
                    alertMessage = item.error?.localizedDescription ?? "Could not load the video."
                    showingAlert = true
                    return
                default:
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        .onDisappear {
            player?.pause()
            // Leaving the screen must not leave a Live Activity stuck on the lock screen
            if isCompressing {
                exportTask?.cancel()
                cancelAssetRequest()
                activityManager.cancel()
            } else {
                activityManager.endBackgroundTask()
            }
            // Nothing may stay parked on a continuation after the view is gone
            backgroundGraceTask?.cancel()
            backgroundGraceTask = nil
            resumeForegroundWaiters()
            if isAccessingScopedResource, case .file(let url) = source {
                url.stopAccessingSecurityScopedResource()
                isAccessingScopedResource = false
            }
            PreviewAudioSession.deactivate()
        }
        // iOS won't run the encoder in the background, so bank what is done
        // rather than letting the system kill it mid-frame.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            guard isCompressing, !isPaused else { return }
            backgroundGraceTask?.cancel()
            backgroundGraceTask = Task {
                // Spend the runtime iOS grants a backgrounded app, then bank a
                // checkpoint while there is still time to close the file
                // cleanly. A short export finishes inside this window.
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                requestGracefulStop()
            }
        }
        // Back in front: carry on from the checkpoint.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            backgroundGraceTask?.cancel()
            backgroundGraceTask = nil
            resumeForegroundWaiters()
            
            // Interrupted before the encoder even started: no sitting is
            // parked waiting, so start the download over.
            if isPaused, exportTask == nil, isCompressing {
                isPaused = false
                startCompression()
            }
        }
        .fileMover(isPresented: $showingFileMover, file: compressedVideoURL) { result in
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                alertMessage = "Error saving: \(error.localizedDescription)"
                showingAlert = true
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // MARK: - Logic Functions
    
    /// No deleting once work is under way, or while the result is on screen.
    private var isDeleteDisabled: Bool {
        isCompressing || showingSuccessModal || isPaused
    }

    func deleteVideoWithoutCompressing() {
        // The authoritative check: a stale toolbar must not delete anything.
        guard !isDeleteDisabled else { return }
        guard case .photo(let asset) = source else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.dismiss()
                } else if let error = error {
                    self.handleError(error.localizedDescription)
                }
            }
        }
    }
    
    /// Size in bytes of the original video, for either source.
    func originalByteCount() -> Int64 {
        switch source {
        case .photo(let asset):
            return asset.totalResourceByteCount
        case .file(let url):
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
    }
    
    /// Size and name of the original, fetched off the main thread so tapping
    /// Compress never waits on Photos.
    func loadMetadata() {
        if case .file(let url) = source {
            displayName = url.lastPathComponent
        }
        let alreadyScoped = isAccessingScopedResource

        DispatchQueue.global(qos: .userInitiated).async {
            let bytes: Int64
            var name: String?

            switch source {
            case .photo(let asset):
                let info = asset.resourceInfo
                bytes = info.byteCount
                name = info.originalFilename
            case .file(let url):
                // Don't touch the scope the player is already holding open
                let didStart = alreadyScoped ? false : url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                bytes = Int64(values?.fileSize ?? 0)
            }

            DispatchQueue.main.async {
                self.originalBytes = bytes
                self.originalSizeString = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                if let name = name {
                    self.displayName = name
                }
            }
        }
    }
    
    func loadVideoPlayer() {
        // onAppear can fire more than once per push; a second request would
        // download the preview all over again.
        guard !hasRequestedPreview else { return }
        hasRequestedPreview = true

        switch source {
        case .photo(let asset):
            previewStartTime = Date()

            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            // The preview only needs to be watchable, so take the cheapest
            // copy Photos can hand over. The full-quality original is
            // downloaded later, when compression actually starts.
            options.deliveryMode = .fastFormat
            options.progressHandler = { progress, _, _, _ in
                DispatchQueue.main.async {
                    // Only publish whole percents: each write redraws the screen
                    let shown = Int((self.previewDownloadProgress ?? -1) * 100)
                    guard Int(progress * 100) != shown else { return }

                    self.previewDownloadProgress = progress
                    if let start = self.previewStartTime {
                        self.previewDownloadETA = Self.remainingTimeString(progress: progress, since: start)
                    }
                }
            }

            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                DispatchQueue.main.async {
                    self.previewDownloadProgress = nil
                    self.previewDownloadETA = nil
                    if let playerItem = playerItem {
                        playerItem.applyPreviewQualityLimits()
                        self.player = AVPlayer(playerItem: playerItem)
                        self.playerGeneration += 1
                    } else if (info?[PHImageCancelledKey] as? Bool) != true {
                        self.hasRequestedPreview = false
                        self.alertMessage = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "Could not load video."
                        self.showingAlert = true
                    }
                }
            }
        case .file(let url):
            // Keep access open for playback and export; released in onDisappear
            if !isAccessingScopedResource {
                isAccessingScopedResource = url.startAccessingSecurityScopedResource()
            }
            let item = AVPlayerItem(asset: AVURLAsset(url: url))
            item.applyPreviewQualityLimits()
            self.player = AVPlayer(playerItem: item)
            self.playerGeneration += 1
        }
    }
    
    /// Shown until the player has a frame to display.
    private var previewPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.92)

            VStack(spacing: 10) {
                if let download = previewDownloadProgress {
                    // iCloud copy has to come down before it can play
                    ProgressView(value: download)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(width: 180)
                    Text("Downloading preview from iCloud… \(Int(download * 100))%")
                    if let eta = previewDownloadETA {
                        Text(eta).font(.caption2)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                    Text(player == nil ? "Loading preview…" : "Preparing preview…")
                }
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
    }

    /// Progress shown in the blocking overlay: the iCloud fetch first, then the export.
    private var overlayProgress: Float {
        isPreparingAsset ? Float(prepareProgress) : progress
    }

    private var overlayStatus: String {
        if isPaused { return "Paused — continues where it stopped" }
        guard isPreparingAsset else { return "Compressing..." }
        return prepareProgress > 0 ? "Downloading from iCloud…" : "Preparing video…"
    }

    /// "45s left" / "2:05 left" from a 0...1 fraction and when the work began.
    static func remainingTimeString(progress: Double, since start: Date) -> String? {
        // Below a few percent the estimate is wild, so say nothing yet.
        guard progress > 0.02 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = (elapsed / progress) - elapsed
        guard remaining.isFinite, remaining >= 0 else { return nil }

        if remaining < 60 {
            return "\(Int(remaining))s left"
        }
        let minutes = Int(remaining / 60)
        let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d left", minutes, seconds)
    }

    func startCompression() {
        // Free the video layer: it is hidden behind the overlay anyway, and the
        // encoder should not have to share the decoder with it.
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        progress = 0.0
        progressAtSessionStart = 0
        prepareProgress = 0.0
        prepareETA = ""
        timeRemainingString = "Calculating..."
        withAnimation { isCompressing = true }

        activityManager.beginBackgroundTask(onExpiration: requestGracefulStop)

        // Requesting a Live Activity blocks for a moment, so let the overlay
        // paint first instead of stalling the tap.
        DispatchQueue.main.async {
            self.activityManager.requestNotificationPermissionIfNeeded()
            self.activityManager.start(videoName: self.displayName)
        }

        switch source {
        case .file(let url):
            beginExport(for: AVURLAsset(url: url))
        case .photo(let asset):
            // The export needs the real original, which for an iCloud video
            // means downloading it now, with progress the user can see.
            isPreparingAsset = true
            prepareStartTime = Date()

            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.progressHandler = { progress, _, _, _ in
                DispatchQueue.main.async {
                    self.prepareProgress = progress
                    if let start = self.prepareStartTime {
                        self.prepareETA = Self.remainingTimeString(progress: progress, since: start) ?? ""
                    }
                    self.activityManager.update(phase: .downloading,
                                                progress: progress,
                                                statusText: "Downloading from iCloud",
                                                etaText: self.prepareETA.isEmpty ? nil : self.prepareETA)
                }
            }

            assetRequestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                DispatchQueue.main.async {
                    self.assetRequestID = nil
                    self.isPreparingAsset = false

                    // A cancel from the background handler is not a real failure
                    if (info?[PHImageCancelledKey] as? Bool) == true { return }

                    guard let avAsset = avAsset else {
                        let message = (info?[PHImageErrorKey] as? Error)?.localizedDescription
                        self.handleError(message ?? "Could not load video for compression.")
                        return
                    }
                    self.beginExport(for: avAsset)
                }
            }
        }
    }

    private func cancelAssetRequest() {
        if let id = assetRequestID {
            PHImageManager.default().cancelImageRequest(id)
            assetRequestID = nil
        }
    }

    /// iOS will not run the encoder while the app is in the background, so
    /// ask the pipeline to finalise what it has. Nothing already encoded is
    /// lost: the next run picks up from the checkpoint it reports.
    private func requestGracefulStop() {
        guard isCompressing, !isPaused else { return }
        
        backgroundGraceTask?.cancel()
        backgroundGraceTask = nil
        isPaused = true
        stopSignal?.requestStop()
        
        // A download, unlike an encode, is cheap to restart
        cancelAssetRequest()
        if isPreparingAsset {
            isPreparingAsset = false
            prepareProgress = 0
        }
        activityManager.pause(progress: Double(overlayProgress))
    }
    
    /// Suspends the export until the app is back in front.
    private func waitUntilForeground() async {
        guard UIApplication.shared.applicationState != .active else { return }
        await withCheckedContinuation { continuation in
            foregroundWaiters.append(continuation)
        }
    }
    
    private func resumeForegroundWaiters() {
        let waiting = foregroundWaiters
        foregroundWaiters = []
        waiting.forEach { $0.resume() }
    }
    
    private func beginExport(for assetToCompress: AVAsset) {
        let outputFileName: String
        switch source {
        case .photo:
            outputFileName = UUID().uuidString + ".mp4"
        case .file(let url):
            // Readable name so the saved file is recognisable in Files
            let base = url.deletingPathExtension().lastPathComponent
            outputFileName = "\(base)-compressed-\(UUID().uuidString.prefix(6)).mp4"
        }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        
        try? FileManager.default.removeItem(at: outputURL)
        
        segmentURLs = []
        resumeAt = .zero
        startTime = Date()
        
        exportTask = Task {
            do {
                try await runResumableExport(asset: assetToCompress, to: outputURL)
                exportDidFinish(outputURL: outputURL)
            } catch is CancellationError {
                // Whoever cancelled already put the UI in the right state
                discardSegments()
            } catch let pipelineError {
                discardSegments()
                
                // The fast pipeline could not handle this file. The system
                // exporter copes with more exotic inputs, so try it once.
                do {
                    try? FileManager.default.removeItem(at: outputURL)
                    try await exportUsingSystemSession(asset: assetToCompress, to: outputURL)
                    exportDidFinish(outputURL: outputURL)
                } catch is CancellationError {
                    // Same as above
                } catch {
                    handleError(pipelineError.localizedDescription)
                }
            }
        }
    }
    
    /// Compresses in as many sittings as it takes. Each sitting ends either at
    /// the end of the video or when the app is sent to the background, and the
    /// next one starts where the last stopped.
    private func runResumableExport(asset: AVAsset, to outputURL: URL) async throws {
        var retriesAfterFailure = 0
        
        while true {
            let signal = VideoCompressor.StopSignal()
            stopSignal = signal
            
            let segmentURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("segment-\(UUID().uuidString).mp4")
            var interruptedAt: CMTime?
            
            do {
                let outcome = try await VideoCompressor.compress(
                    asset: asset,
                    to: segmentURL,
                    quality: selectedQuality,
                    from: resumeAt,
                    stopSignal: signal
                ) { fraction in
                    DispatchQueue.main.async { publishExportProgress(fraction) }
                }
                
                retriesAfterFailure = 0
                
                switch outcome {
                case .completed:
                    segmentURLs.append(segmentURL)
                    try await VideoCompressor.join(segments: segmentURLs, to: outputURL)
                    discardSegments()
                    return
                    
                case .interrupted(let resumeTime, let wroteSegment):
                    if wroteSegment {
                        segmentURLs.append(segmentURL)
                        // Guard against a stall: a segment that advances
                        // nothing would loop forever.
                        guard resumeTime > resumeAt else {
                            throw VideoCompressorError.failed("Compression could not make progress.")
                        }
                        resumeAt = resumeTime
                    } else {
                        try? FileManager.default.removeItem(at: segmentURL)
                    }
                    interruptedAt = resumeTime
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: segmentURL)
                
                // The encoder can be torn down before a clean stop lands. Only
                // this sitting is lost, so retry from the last checkpoint.
                let worthRetrying = isPaused || UIApplication.shared.applicationState != .active
                retriesAfterFailure += 1
                guard worthRetrying, retriesAfterFailure <= 3 else { throw error }
                interruptedAt = resumeAt
            }
            
            // Hold here, paused, until the app is in front again.
            if interruptedAt != nil {
                await waitUntilForeground()
                try Task.checkCancellation()
                resumeAfterPause()
            }
        }
    }
    
    private func resumeAfterPause() {
        isPaused = false
        startTime = Date()
        progressAtSessionStart = progress
        // Fresh runtime for this sitting
        activityManager.beginBackgroundTask(onExpiration: requestGracefulStop)
        activityManager.update(phase: .compressing,
                               progress: Double(progress),
                               statusText: "Compressing",
                               etaText: nil,
                               force: true)
    }
    
    private func discardSegments() {
        segmentURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        segmentURLs = []
    }
    
    private func exportDidFinish(outputURL: URL) {
        exportTask = nil
        isPaused = false
        backgroundGraceTask?.cancel()
        backgroundGraceTask = nil
        compressedVideoURL = outputURL
        calculateResults(outputURL: outputURL)
        isCompressing = false
        activityManager.finish(savedText: completionSummary)
        withAnimation { showingSuccessModal = true }
    }

    /// Fallback for anything the reader/writer pipeline refuses.
    private func exportUsingSystemSession(asset: AVAsset, to outputURL: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: selectedQuality.avPresetName) else {
            throw VideoCompressorError.failed("Could not create export session.")
        }
        // Fast start costs another pass and buys nothing for a local file
        session.shouldOptimizeForNetworkUse = false

        let progressObserver = Task {
            for await state in session.states(updateInterval: 0.25) {
                if case .exporting(let progress) = state {
                    publishExportProgress(progress.fractionCompleted)
                }
            }
        }
        defer { progressObserver.cancel() }

        try await session.export(to: outputURL, as: .mp4)
    }
    
    /// One line for the completion notification.
    private var completionSummary: String {
        if sizeIncreased {
            return "\(displayName) got bigger (\(compressedSizeString)). Open the app to discard it."
        }
        return "\(displayName) is now \(compressedSizeString) — you saved \(savedSizeString)."
    }
    
    /// Each write redraws the screen, so only publish what the user can see.
    private func publishExportProgress(_ fraction: Double) {
        let percentChanged = Int(fraction * 100) != Int(progress * 100)
        
        var remainingText: String?
        if let start = startTime {
            // Time left for this sitting is the time left overall, but the
            // sitting began part-way through the video.
            let alreadyDone = Double(progressAtSessionStart)
            let sessionFraction = (fraction - alreadyDone) / max(1 - alreadyDone, 0.001)
            remainingText = Self.remainingTimeString(progress: sessionFraction, since: start)
        }
        let etaChanged = remainingText != nil && remainingText != timeRemainingString
        
        guard percentChanged || etaChanged else { return }
        
        if percentChanged {
            progress = Float(fraction)
        }
        if etaChanged, let remainingText = remainingText {
            timeRemainingString = remainingText
        }
        
        activityManager.update(phase: .compressing,
                               progress: fraction,
                               statusText: "Compressing",
                               etaText: timeRemainingString)
    }
    
    func calculateResults(outputURL: URL) {
        // Cached at load; only recomputed if that somehow never finished
        let originalBytes = self.originalBytes > 0 ? self.originalBytes : originalByteCount()
        
        var compressedBytes: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let size = attributes[.size] as? Int64 {
            compressedBytes = size
        }
        
        self.compressedSizeString = ByteCountFormatter.string(fromByteCount: compressedBytes, countStyle: .file)
        
        if compressedBytes > originalBytes {
            self.sizeIncreased = true
            let extraBytes = compressedBytes - originalBytes
            self.savedSizeString = "+" + ByteCountFormatter.string(fromByteCount: extraBytes, countStyle: .file)
        } else {
            self.sizeIncreased = false
            let savedBytes = originalBytes - compressedBytes
            self.savedSizeString = ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
        }
    }
    
    func saveCompressedOnly() {
        guard let url = compressedVideoURL else { return }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.dismiss()
                } else {
                    self.alertMessage = "Error saving: \(error?.localizedDescription ?? "Unknown")"
                    self.showingAlert = true
                }
            }
        }
    }
    
    func saveCompressedAndDeleteOriginal() {
        guard let url = compressedVideoURL else { return }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            if case .photo(let asset) = self.source {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.dismiss()
                } else {
                    self.alertMessage = "Error: \(error?.localizedDescription ?? "Unknown")"
                    self.showingAlert = true
                }
            }
        }
    }
    
    func handleError(_ message: String) {
        isPreparingAsset = false
        isPaused = false
        exportTask = nil
        activityManager.fail(message: message)
        withAnimation { isCompressing = false }

        // Bring the preview back so the screen is usable again
        if player == nil {
            hasRequestedPreview = false
            loadVideoPlayer()
        }
        alertMessage = message
        showingAlert = true
    }
}
