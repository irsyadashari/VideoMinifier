//
//  CompressorView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//

import SwiftUI
import PhotosUI
import AVKit

struct CompressorView: View {
    let asset: PHAsset
    
    // UI State
    @State private var player: AVPlayer?
    @State private var selectedQuality: QualityOption = .medium
    @State private var isCompressing = false
    @State private var progress: Float = 0.0
    
    // ETA Calculation State
    @State private var timeRemainingString: String = "Calculating..."
    @State private var startTime: Date?
    @State private var timer: Timer?
    
    // File Size State
    @State private var originalSizeString: String = "Calculating..."
    @State private var compressedSizeString: String = ""
    @State private var savedSizeString: String = ""
    @State private var sizeIncreased = false
    
    // Alerts & Modals
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSuccessModal = false
    @State private var compressedVideoURL: URL?
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            // MARK: - Main Content Layer
            VStack(spacing: 16) {
                
                // 1. Video Preview Player
                ZStack {
                    if let player = player {
                        VideoPlayer(player: player)
                            .onAppear { player.play() }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(ProgressView())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(12)
                .padding([.horizontal, .top])
                
                // Show Original File Size
                Text("Original Size: \(originalSizeString)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
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
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            VStack(spacing: 8) {
                                ProgressView(value: progress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                    .scaleEffect(x: 1, y: 2, anchor: .center)
                                
                                HStack {
                                    Text("Compressing...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text(timeRemainingString)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 40)
                            
                            Text("Please do not close the app.")
                                .font(.footnote)
                                .foregroundColor(.gray.opacity(0.8))
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
                                if !sizeIncreased {
                                    Button(action: saveCompressedAndDeleteOriginal) {
                                        Text("Delete Original & Save New")
                                            .bold().frame(maxWidth: .infinity).padding()
                                            .background(Color.red).foregroundColor(.white).cornerRadius(10)
                                    }
                                }
                                Button(action: sizeIncreased ? { presentationMode.wrappedValue.dismiss() } : saveCompressedOnly) {
                                    Text(sizeIncreased ? "Cancel & Discard" : "Keep Original & Save New")
                                        .frame(maxWidth: .infinity).padding()
                                        .background(Color.primary.opacity(0.05)).foregroundColor(.primary).cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1), lineWidth: 1))
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
                Button(action: deleteVideoWithoutCompressing) {
                    Image(systemName: "trash")
                        .foregroundColor(.red) // Red color for danger
                }
                // Disable button if busy or showing results
                .disabled(isCompressing || showingSuccessModal)
            }
        }
        
        .onAppear {
            loadVideoPlayer()
            calculateOriginalSize()
        }
        .onDisappear {
            player?.pause()
            stopTimer()
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // MARK: - Logic Functions
    
    func deleteVideoWithoutCompressing() {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([self.asset] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.presentationMode.wrappedValue.dismiss()
                } else if let error = error {
                    self.handleError(error.localizedDescription)
                }
            }
        }
    }
    
    func calculateOriginalSize() {
        let resources = PHAssetResource.assetResources(for: asset)
        var size: Int64 = 0
        for resource in resources {
            if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                size += fileSize
            }
        }
        self.originalSizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    func loadVideoPlayer() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
            DispatchQueue.main.async {
                if let avAsset = avAsset {
                    let playerItem = AVPlayerItem(asset: avAsset)
                    self.player = AVPlayer(playerItem: playerItem)
                } else {
                    self.alertMessage = "Could not load video."
                    self.showingAlert = true
                }
            }
        }
    }
    
    func startCompression() {
        guard let currentItem = player?.currentItem else { return }
        let assetToCompress = currentItem.asset
        
        player?.pause()
        progress = 0.0
        timeRemainingString = "Calculating..."
        withAnimation { isCompressing = true }
        
        let outputFileName = UUID().uuidString + ".mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: assetToCompress, presetName: selectedQuality.avPresetName) else {
            handleError("Could not create export session.")
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        startTime = Date()
        startProgressTimer(for: exportSession)
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                self.stopTimer()
                
                switch exportSession.status {
                case .completed:
                    self.compressedVideoURL = outputURL
                    self.calculateResults(outputURL: outputURL)
                    self.isCompressing = false
                    withAnimation {
                        self.showingSuccessModal = true
                    }
                case .failed, .cancelled:
                    self.handleError(exportSession.error?.localizedDescription ?? "Unknown error")
                default:
                    break
                }
            }
        }
    }
    
    func startProgressTimer(for exportSession: AVAssetExportSession) {
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let currentProgress = exportSession.progress
            self.progress = currentProgress
            
            if let start = self.startTime, currentProgress > 0.0 {
                let timeElapsed = Date().timeIntervalSince(start)
                let estimatedTotalTime = timeElapsed / Double(currentProgress)
                let remaining = estimatedTotalTime - timeElapsed
                
                if remaining < 60 {
                    self.timeRemainingString = "\(Int(remaining))s left"
                } else {
                    let mins = Int(remaining / 60)
                    let secs = Int(remaining.truncatingRemainder(dividingBy: 60))
                    self.timeRemainingString = String(format: "%d:%02d left", mins, secs)
                }
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func calculateResults(outputURL: URL) {
        let resources = PHAssetResource.assetResources(for: asset)
        var originalBytes: Int64 = 0
        for resource in resources {
            if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                originalBytes += fileSize
            }
        }
        
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
                    self.presentationMode.wrappedValue.dismiss()
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
            PHAssetChangeRequest.deleteAssets([self.asset] as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.presentationMode.wrappedValue.dismiss()
                } else {
                    self.alertMessage = "Error: \(error?.localizedDescription ?? "Unknown")"
                    self.showingAlert = true
                }
            }
        }
    }
    
    func handleError(_ message: String) {
        stopTimer()
        withAnimation { isCompressing = false }
        alertMessage = message
        showingAlert = true
    }
}
