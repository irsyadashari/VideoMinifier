//
//  VideoCompressor.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/13/26.
//
//  A reader/writer pipeline instead of AVAssetExportSession. The win is not
//  more CPU threads — H.264/HEVC encoding runs on a fixed-function hardware
//  block either way — it is in not wasting work:
//
//   * no "optimize for network use" pass over the finished file
//   * audio copied through untouched when it is already AAC
//   * video and audio pumped on separate queues, so they overlap
//   * expectsMediaDataInRealTime = false, so the encoder is never paced
//   * alwaysCopiesSampleData = false, so 4K frames are not memcpy'd
//   * an explicit bitrate, instead of whatever a preset decides
//
//  It also stops on request, finalising what it has into a playable segment
//  and reporting where to pick up. That is what lets a compression survive
//  the app being sent to the background: iOS will not let the encoder keep
//  running there, but the work already done does not have to be thrown away.
//

import AVFoundation
import VideoToolbox

enum VideoCompressorError: LocalizedError {
    case noVideoTrack
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "This file has no video track to compress."
        case .failed(let reason):
            return reason
        }
    }
}

enum CompressionOutcome {
    /// The whole asset was written.
    case completed
    /// Stopped on request. Anything written is finalised and playable.
    case interrupted(resumeAt: CMTime, wroteSegment: Bool)
}

struct VideoCompressor {

    /// Asks a running compression to wrap up at the next frame boundary.
    nonisolated final class StopSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var requested = false

        var isStopRequested: Bool { lock.withLock { requested } }
        func requestStop() { lock.withLock { requested = true } }
    }

    /// Re-encodes `asset` from `startTime` into `outputURL`.
    ///
    /// `onProgress` reports progress through the *whole* asset, not the
    /// segment, so a resumed run carries on from where the last one stopped.
    /// It is only called when the whole percentage changes.
    nonisolated static func compress(asset: AVAsset,
                                     to outputURL: URL,
                                     quality: QualityOption,
                                     from startTime: CMTime = .zero,
                                     stopSignal: StopSignal,
                                     onProgress: @escaping @Sendable (Double) -> Void) async throws -> CompressionOutcome {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoCompressorError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let sourceDataRate = try await videoTrack.load(.estimatedDataRate)
        let isHDR = try await videoTrack.load(.mediaCharacteristics).contains(.containsHDRVideo)

        nonisolated(unsafe) let reader = try AVAssetReader(asset: asset)
        nonisolated(unsafe) let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        // Fast-start interleaving needs another pass over the output, and this
        // file is going straight into the library, not onto a web server.
        writer.shouldOptimizeForNetworkUse = false

        // Only read the part that is still missing.
        if startTime > .zero {
            reader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
        }

        // MARK: Video

        let targetSize = fittedSize(for: naturalSize, within: quality.maximumDimensions)
        let frameRate = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30

        // 10-bit in, 10-bit out for HDR. Reading HLG frames as 8-bit and
        // re-encoding them as H.264 is what makes "compressed" clips look
        // washed out, so HDR stays on the HEVC path.
        let pixelFormat = isHDR
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        nonisolated(unsafe) let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        )
        videoOutput.alwaysCopiesSampleData = false

        nonisolated(unsafe) let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings(targetSize: targetSize,
                                          frameRate: frameRate,
                                          isHDR: isHDR,
                                          sourceDataRate: sourceDataRate)
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform

        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw VideoCompressorError.failed("This video's format can't be re-encoded.")
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        // MARK: Audio

        nonisolated(unsafe) let audioPair = try await makeAudioPair(for: asset, reader: reader, writer: writer)

        // MARK: Run

        guard reader.startReading() else {
            throw VideoCompressorError.failed(reader.error?.localizedDescription ?? "Could not read the video.")
        }
        guard writer.startWriting() else {
            throw VideoCompressorError.failed(writer.error?.localizedDescription ?? "Could not write the video.")
        }
        // Per AVAssetWriter: this start time maps to time zero in the output,
        // so every segment is a file that begins at zero.
        writer.startSession(atSourceTime: startTime)

        let cancelled = Flag()
        let reported = Counter()
        let lastVideoEnd = TimeBox()
        let totalSeconds = max(duration.seconds, 0.001)

        let shouldStop: @Sendable () -> Bool = { cancelled.isSet || stopSignal.isStopRequested }

        return try await withTaskCancellationHandler {
            async let video: Void = pump(input: videoInput,
                                         output: videoOutput,
                                         label: "compressor.video",
                                         shouldStop: shouldStop) { end in
                lastVideoEnd.set(end)
                let fraction = min(max(end.seconds / totalSeconds, 0), 1)
                if reported.update(to: Int(fraction * 100)) {
                    onProgress(fraction)
                }
            }
            async let audio: Void = pumpIfPresent(audioPair, shouldStop: shouldStop)
            _ = await (video, audio)

            if cancelled.isSet {
                throw CancellationError()
            }

            // A read that died part-way leaves the pumps thinking they are
            // done, which would hand back a truncated file as a success.
            if reader.status == .failed {
                writer.cancelWriting()
                throw VideoCompressorError.failed(
                    reader.error?.localizedDescription ?? "Could not read the whole video."
                )
            }

            // Asked to stop before the end: keep what was written.
            if stopSignal.isStopRequested, reader.status != .completed {
                let stopTime = lastVideoEnd.value
                guard stopTime.isNumeric, stopTime > startTime else {
                    // Stopped too early to have written anything useful
                    writer.cancelWriting()
                    return .interrupted(resumeAt: startTime, wroteSegment: false)
                }

                // Trims audio that ran past the last video frame, so the two
                // tracks end together and the next segment lines up.
                writer.endSession(atSourceTime: stopTime)
                await writer.finishWriting()

                guard writer.status == .completed else {
                    throw VideoCompressorError.failed(
                        writer.error?.localizedDescription ?? "Could not save the partial video."
                    )
                }
                return .interrupted(resumeAt: stopTime, wroteSegment: true)
            }

            await writer.finishWriting()

            guard writer.status == .completed else {
                if writer.status == .cancelled { throw CancellationError() }
                throw VideoCompressorError.failed(writer.error?.localizedDescription ?? "The export did not finish.")
            }
            return .completed
        } onCancel: {
            cancelled.set()
            reader.cancelReading()
            writer.cancelWriting()
        }
    }

    /// Stitches segments into one file. The samples are already encoded, so
    /// this is a remux rather than a second pass through the encoder.
    nonisolated static func join(segments: [URL], to outputURL: URL) async throws {
        guard let first = segments.first else {
            throw VideoCompressorError.failed("Nothing was compressed.")
        }
        guard segments.count > 1 else {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: first, to: outputURL)
            return
        }

        let composition = AVMutableComposition()
        var videoTrack: AVMutableCompositionTrack?
        var audioTrack: AVMutableCompositionTrack?
        var videoCursor = CMTime.zero
        var audioCursor = CMTime.zero

        for url in segments {
            let segment = AVURLAsset(url: url)

            if let source = try await segment.loadTracks(withMediaType: .video).first {
                let range = try await source.load(.timeRange)
                if videoTrack == nil {
                    videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
                    videoTrack?.preferredTransform = try await source.load(.preferredTransform)
                }
                try videoTrack?.insertTimeRange(range, of: source, at: videoCursor)
                videoCursor = CMTimeAdd(videoCursor, range.duration)
            }

            if let source = try await segment.loadTracks(withMediaType: .audio).first {
                let range = try await source.load(.timeRange)
                if audioTrack == nil {
                    audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try audioTrack?.insertTimeRange(range, of: source, at: audioCursor)
                audioCursor = CMTimeAdd(audioCursor, range.duration)
            }
        }

        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetPassthrough) else {
            throw VideoCompressorError.failed("Could not join the compressed parts.")
        }
        session.shouldOptimizeForNetworkUse = false

        try? FileManager.default.removeItem(at: outputURL)
        try await runExport(session, to: outputURL)
    }
    
    /// `export(to:as:)` and `states(updateInterval:)` landed in iOS 18, so on
    /// anything older this falls back to the original callback API.
    nonisolated static func runExport(_ session: AVAssetExportSession,
                                      to outputURL: URL,
                                      onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard #available(iOS 18.0, *) else {
            try await legacyExport(session, to: outputURL, onProgress: onProgress)
            return
        }
        
        let observer: Task<Void, Never>? = onProgress.map { report in
            Task {
                for await state in session.states(updateInterval: 0.25) {
                    if case .exporting(let progress) = state {
                        report(progress.fractionCompleted)
                    }
                }
            }
        }
        defer { observer?.cancel() }
        
        try await session.export(to: outputURL, as: .mp4)
    }
    
    // Deprecated on purpose: marking the function itself deprecated is what
    // keeps the old API's warnings from leaking into every build.
    @available(iOS, deprecated: 18.0)
    private nonisolated static func legacyExport(_ session: AVAssetExportSession,
                                                 to outputURL: URL,
                                                 onProgress: (@Sendable (Double) -> Void)?) async throws {
        nonisolated(unsafe) let session = session
        session.outputURL = outputURL
        session.outputFileType = .mp4
        
        let observer: Task<Void, Never>? = onProgress.map { report in
            Task {
                while !Task.isCancelled {
                    report(Double(session.progress))
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
        defer { observer?.cancel() }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(
                        throwing: session.error ?? VideoCompressorError.failed("The export did not finish.")
                    )
                }
            }
        }
    }

    // MARK: - Pipeline

    /// Wires up the audio track, preferring to copy AAC samples through
    /// untouched: no decode, no encode, no chance of mangling a channel layout.
    ///
    /// Returns nil only when the video genuinely has no audio. If there is a
    /// track that cannot be wired up, this throws rather than quietly handing
    /// back a silent video — the caller's fallback keeps the sound.
    private nonisolated static func makeAudioPair(
        for asset: AVAsset,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) async throws -> (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let formats = try await audioTrack.load(.formatDescriptions)
        let isAAC = formats.contains { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC }

        // 1. Straight copy. A passthrough input has no output settings to
        //    describe it, so without a format hint the writer cannot tell
        //    whether it can carry these samples and refuses the input.
        if isAAC, let sourceFormat = formats.first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio,
                                           outputSettings: nil,
                                           sourceFormatHint: sourceFormat)
            input.expectsMediaDataInRealTime = false

            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                return (output, input)
            }
        }

        // 2. Anything else gets decoded and re-encoded as AAC, matching the
        //    source's own rate and channels so the encoder has no reason to
        //    reject the stream.
        var channels = 2
        var sampleRate = 44_100.0
        var channelLayout: Data?

        if let sourceFormat = formats.first {
            if let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(sourceFormat)?.pointee {
                channels = max(1, Int(basicDescription.mChannelsPerFrame))
                if basicDescription.mSampleRate > 0 {
                    sampleRate = basicDescription.mSampleRate
                }
            }
            var layoutSize = 0
            if let layout = CMAudioFormatDescriptionGetChannelLayout(sourceFormat, sizeOut: &layoutSize),
               layoutSize > 0 {
                channelLayout = Data(bytes: layout, count: layoutSize)
            }
        }

        // AAC needs an explicit layout above stereo; without one, downmix.
        if channels > 2, channelLayout == nil {
            channels = 2
        }

        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: channels,
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: channels > 2 ? 256_000 : 128_000,
        ]
        if channels > 2, let channelLayout = channelLayout {
            settings[AVChannelLayoutKey] = channelLayout
        }

        let output = AVAssetReaderTrackOutput(track: audioTrack,
                                              outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        output.alwaysCopiesSampleData = false
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        guard reader.canAdd(output), writer.canAdd(input) else {
            throw VideoCompressorError.failed("This video's audio track can't be re-encoded.")
        }
        reader.add(output)
        writer.add(input)
        return (output, input)
    }

    private nonisolated static func pumpIfPresent(
        _ pair: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?,
        shouldStop: @escaping @Sendable () -> Bool
    ) async {
        guard let pair = pair else { return }
        await pump(input: pair.input, output: pair.output, label: "compressor.audio", shouldStop: shouldStop)
    }

    /// `onAppended` reports the end time of each sample that made it into the
    /// file, which is both the progress signal and the resume point.
    private nonisolated static func pump(input: AVAssetWriterInput,
                                         output: AVAssetReaderOutput,
                                         label: String,
                                         shouldStop: @escaping @Sendable () -> Bool,
                                         onAppended: (@Sendable (CMTime) -> Void)? = nil) async {
        let queue = DispatchQueue(label: label, qos: .userInitiated)
        // Safe to use from a single queue, which is exactly how they are used
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) let output = output

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)

            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard !shouldStop(),
                          let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        once.resume()
                        return
                    }

                    guard input.append(sample) else {
                        input.markAsFinished()
                        once.resume()
                        return
                    }

                    if let onAppended = onAppended {
                        let start = CMSampleBufferGetPresentationTimeStamp(sample)
                        let length = CMSampleBufferGetDuration(sample)
                        onAppended(length.isNumeric ? CMTimeAdd(start, length) : start)
                    }
                }
            }
        }
    }

    // MARK: - Settings

    /// Scales to fit inside `box` without upscaling, keeping aspect ratio and
    /// landing on even dimensions, which the encoders require.
    private nonisolated static func fittedSize(for size: CGSize, within box: CGSize) -> CGSize {
        let sourceLong = max(size.width, size.height)
        let sourceShort = min(size.width, size.height)
        guard sourceLong > 0, sourceShort > 0 else { return box }

        let boxLong = max(box.width, box.height)
        let boxShort = min(box.width, box.height)
        let scale = min(1, min(boxLong / sourceLong, boxShort / sourceShort))

        func even(_ value: CGFloat) -> CGFloat {
            max(16, ((value * scale) / 2).rounded() * 2)
        }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    private nonisolated static func videoSettings(targetSize: CGSize,
                                                  frameRate: Double,
                                                  isHDR: Bool,
                                                  sourceDataRate: Float) -> [String: Any] {
        let bitsPerPixel = isHDR ? 0.065 : 0.10
        var bitRate = Double(targetSize.width) * Double(targetSize.height) * frameRate * bitsPerPixel

        // Never spend more bits than the original did; that is how a
        // "compressed" file ends up bigger than what it replaced.
        if sourceDataRate > 0 {
            bitRate = min(bitRate, Double(sourceDataRate) * 0.9)
        }
        bitRate = min(max(bitRate, 500_000), 20_000_000)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: Int(bitRate),
            AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
            AVVideoMaxKeyFrameIntervalKey: Int((frameRate * 2).rounded()),
            AVVideoProfileLevelKey: isHDR
                ? (kVTProfileLevel_HEVC_Main10_AutoLevel as String)
                : AVVideoProfileLevelH264HighAutoLevel,
        ]

        return [
            AVVideoCodecKey: isHDR ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }
}

// MARK: - Small thread-safe helpers

private nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Lets the pipeline report only whole-percent changes.
private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = -1

    func update(to new: Int) -> Bool {
        lock.withLock {
            guard new != value else { return false }
            value = new
            return true
        }
    }
}

private nonisolated final class TimeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var time: CMTime = .invalid

    var value: CMTime { lock.withLock { time } }
    func set(_ newValue: CMTime) { lock.withLock { time = newValue } }
}

/// `requestMediaDataWhenReady` can run its block many times; the continuation
/// must be resumed exactly once.
private nonisolated final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            let value = continuation
            continuation = nil
            return value
        }
        pending?.resume()
    }
}
