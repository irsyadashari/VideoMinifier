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
    
    // File Size State
    @State private var originalSizeString: String = "Calculating..."
    @State private var compressedSizeString: String = ""
    @State private var savedSizeString: String = ""
    
    // Alerts & Modals
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSuccessModal = false // New custom modal for results
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
                
                // NEW: Show Original File Size
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
            .navigationBarBackButtonHidden(isCompressing)
            
            // MARK: - Blocking Loading Overlay
            if isCompressing {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("Compressing Video...")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("This may take a moment.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                    )
            }
            
            // MARK: - Success Modal (Results)
            if showingSuccessModal {
                // 1. Darker dimming (0.6) so the modal stands out more
                Color.black.opacity(0.6)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            
                            Text("Compression Complete!")
                                .font(.title2)
                                .bold()
                            
                            // Comparison Stats
                            HStack(spacing: 40) {
                                VStack {
                                    Text("Before")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(originalSizeString)
                                        .font(.headline)
                                }
                                
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.gray)
                                
                                VStack {
                                    Text("After")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(compressedSizeString)
                                        .font(.headline)
                                }
                            }
                            
                            // Savings Highlight
                            Text("You saved \(savedSizeString)!")
                                .font(.headline)
                                .foregroundColor(.green)
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            
                            // Action Buttons
                            VStack(spacing: 12) {
                                Button(action: saveCompressedAndDeleteOriginal) {
                                    Text("Delete Original & Save New")
                                        .bold()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                
                                Button(action: saveCompressedOnly) {
                                    Text("Keep Original & Save New")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.primary.opacity(0.05)) // Subtle gray background
                                        .foregroundColor(.primary)
                                        .cornerRadius(10)
                                    // Add a border to the button too for clarity
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                        }
                            .padding(24)
                            .background(Color(.systemBackground))
                            .cornerRadius(20)
                        
                        // 2. NEW: Add a crisp border line around the entire modal
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                        
                        // 3. NEW: Stronger, directional shadow for 3D depth
                            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
                            .padding(.horizontal, 40)
                    )
            }
        }
        .navigationTitle("Preview & Compress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVideoPlayer()
            calculateOriginalSize() // Calculate size on load
        }
        .onDisappear {
            player?.pause()
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // MARK: - Logic Functions
    
    func calculateOriginalSize() {
        // PHAsset resources calculation
        let resources = PHAssetResource.assetResources(for: asset)
        var size: Int64 = 0
        
        // Sum up sizes of all resources (video + audio components)
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
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    self.compressedVideoURL = outputURL
                    self.calculateResults(outputURL: outputURL) // Calculate new sizes
                    self.isCompressing = false
                    withAnimation {
                        self.showingSuccessModal = true // Show custom modal
                    }
                case .failed, .cancelled:
                    self.handleError(exportSession.error?.localizedDescription ?? "Unknown error")
                default:
                    break
                }
            }
        }
    }
    
    func calculateResults(outputURL: URL) {
        // 1. Get original size in bytes
        let resources = PHAssetResource.assetResources(for: asset)
        var originalBytes: Int64 = 0
        for resource in resources {
            if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                originalBytes += fileSize
            }
        }
        
        // 2. Get new size in bytes
        var compressedBytes: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let size = attributes[.size] as? Int64 {
            compressedBytes = size
        }
        
        // 3. Format strings
        self.compressedSizeString = ByteCountFormatter.string(fromByteCount: compressedBytes, countStyle: .file)
        
        let savedBytes = max(0, originalBytes - compressedBytes)
        self.savedSizeString = ByteCountFormatter.string(fromByteCount: savedBytes, countStyle: .file)
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
        withAnimation { isCompressing = false }
        alertMessage = message
        showingAlert = true
    }
}
