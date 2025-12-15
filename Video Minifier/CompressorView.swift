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
    @State private var progress: Float = 0.0 // To track export progress
    
    // Alerts
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingCompletionAlert = false // Specific alert for Keep/Delete choice
    @State private var compressedVideoURL: URL? // Store the path to the new file
    
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
                        // Placeholder while loading
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(ProgressView())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(12)
                .padding([.horizontal, .top])
                
                // 2. Bottom Controls Container
                VStack(spacing: 20) {
                    
                    // Quality Selection
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
                    .onTapGesture { }
            }
        }
        .navigationTitle("Preview & Compress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadVideoPlayer()
        }
        .onDisappear {
            player?.pause()
        }
        // General Error Alert
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        // Success / Action Alert
        .alert(isPresented: $showingCompletionAlert) {
            Alert(
                title: Text("Compression Complete"),
                message: Text("Your video has been compressed successfully. Do you want to keep the original video or delete it?"),
                primaryButton: .destructive(Text("Delete Original")) {
                    saveCompressedAndDeleteOriginal()
                },
                secondaryButton: .default(Text("Keep Original")) {
                    saveCompressedOnly()
                }
            )
        }
    }
    
    // MARK: - Logic Functions
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
        
        // 1. Prepare UI
        player?.pause()
        withAnimation { isCompressing = true }
        
        // 2. Define Output URL in Temporary Directory
        let outputFileName = UUID().uuidString + ".mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
        
        // Clean up any previous temp file at this location
        try? FileManager.default.removeItem(at: outputURL)
        
        // 3. Configure Export Session
        guard let exportSession = AVAssetExportSession(asset: assetToCompress, presetName: selectedQuality.avPresetName) else {
            handleError("Could not create export session.")
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // 4. Start Export
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    self.compressedVideoURL = outputURL
                    self.isCompressing = false
                    self.showingCompletionAlert = true
                case .failed, .cancelled:
                    self.handleError(exportSession.error?.localizedDescription ?? "Unknown error")
                default:
                    break
                }
            }
        }
    }
    
    // Option A: Keep Original (Save New Only)
    func saveCompressedOnly() {
        guard let url = compressedVideoURL else { return }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.presentationMode.wrappedValue.dismiss()
                } else {
                    self.alertMessage = "Error saving video: \(error?.localizedDescription ?? "Unknown")"
                    self.showingAlert = true
                }
            }
        }
    }
    
    // Option B: Delete Original (Save New + Delete Old)
    func saveCompressedAndDeleteOriginal() {
        guard let url = compressedVideoURL else { return }
        
        PHPhotoLibrary.shared().performChanges({
            // 1. Create the new compressed video
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            
            // 2. Delete the old original video
            PHAssetChangeRequest.deleteAssets([self.asset] as NSArray)
            
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    // Note: iOS will automatically show a system prompt to confirm deletion.
                    // If user approves, success is true.
                    self.presentationMode.wrappedValue.dismiss()
                } else {
                    self.alertMessage = "Action failed: \(error?.localizedDescription ?? "Unknown")"
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
