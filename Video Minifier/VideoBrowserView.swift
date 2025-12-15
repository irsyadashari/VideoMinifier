//
//  VideoBrowserView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//

import SwiftUI
import Photos

struct VideoBrowserView: View {
    @StateObject private var viewModel = VideoLibraryViewModel()
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack { // Changed Group to ZStack to handle overlay
                if viewModel.hasPermission {
                    if viewModel.assets.count == 0 && !viewModel.isLoading {
                        // Empty State
                        VStack(spacing: 16) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No Videos Found")
                                .font(.headline)
                            Text("It looks like you don't have any videos.")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Grid View
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(0..<viewModel.assets.count, id: \.self) { index in
                                    let asset = viewModel.assets[index]
                                    NavigationLink(destination: CompressorView(asset: asset)) {
                                        VideoThumbnail(asset: asset)
                                            .aspectRatio(1, contentMode: .fit)
                                            .id(asset.localIdentifier) // Explicit ID helps SwiftUI refresh
                                    }
                                }
                            }
                        }
                        // NEW: Blur the list if we are reloading
                        .opacity(viewModel.isLoading ? 0.5 : 1.0)
                    }
                } else {
                    // No Permission View
                    VStack {
                        Image(systemName: "lock.slash").font(.largeTitle).padding()
                        Text("Please allow access to your Photo Library.")
                    }
                }
                
                // MARK: - Loading Overlay
                if viewModel.isLoading {
                    ProgressView("Refreshing Library...")
                        .padding()
                        .background(Color.secondary.opacity(0.2)) // Light background
                        .cornerRadius(10)
                }
            }
            .navigationTitle("Select Video")
            .navigationBarTitleDisplayMode(.inline)
            // MARK: - Force Refresh on Appear
            .onAppear {
                // When we come back from CompressorView, this triggers a fresh reload
                viewModel.fetchVideos()
            }
        }
    }
}
