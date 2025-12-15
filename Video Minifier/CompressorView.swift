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
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    // Environment needed to programmatically dismiss the view later if needed
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
                // CHANGED: Removed fixed aspect ratio.
                // Added maxHeight: .infinity to fill all empty space.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black) // Adds a black background for letterboxing
                .cornerRadius(12)
                .padding([.horizontal, .top]) // Keep margins on sides and top
                
                // 2. Bottom Controls Container
                // We group the Picker and Button together at the bottom
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
                    Button(action: startCompressionTrigger) {
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
                .padding(.bottom) // Add padding at the very bottom of the screen
            }
            // Hides back button during compression
            .navigationBarBackButtonHidden(isCompressing)
            
            
            // MARK: - Blocking Loading Overlay (Same as before)
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
                            Text("Please do not close the app.")
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
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // MARK: - Helper Functions
    
    func loadVideoPlayer() {
        // We need to get the AVAsset from the PHAsset to play it
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true // Allow downloading from iCloud if needed
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
            DispatchQueue.main.async {
                if let avAsset = avAsset {
                    let playerItem = AVPlayerItem(asset: avAsset)
                    self.player = AVPlayer(playerItem: playerItem)
                } else {
                    // Handle error loading video (e.g. iCloud download failed)
                    self.alertMessage = "Could not load video."
                    self.showingAlert = true
                }
            }
        }
    }
    
    func startCompressionTrigger() {
        // Pause playback before starting heavy work
        player?.pause()
        
        withAnimation {
            isCompressing = true
        }
        
        print("Starting compression with preset: \(selectedQuality.avPresetName)")
        
        // --- PLACEHOLDER FOR NEXT STEP ---
        // This is where the actual AVAssetExportSession logic will go.
        // For now, we simulate a 4-second delay so you can see the UI blocking affect.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            // Finish simulation
            withAnimation {
                isCompressing = false
            }
            alertMessage = "Compression finished (Simulation completed)."
            showingAlert = true
            // In real app, you would navigate to the "Save/Replace" screen here.
        }
        // ---------------------------------
    }
}
