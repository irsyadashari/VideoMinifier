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
    
    // Grid Configuration: 3 columns
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.hasPermission {
                    // Check if the fetch result is empty
                    if viewModel.assets.count == 0 {
                        // MARK: - New Empty State
                        VStack(spacing: 16) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No Videos Found")
                                .font(.headline)
                            Text("It looks like you don't have any videos in your library yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    } else {
                        // Existing Grid View
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                // Loop through fetch result indices
                                ForEach(0..<viewModel.assets.count, id: \.self) { index in
                                    let asset = viewModel.assets[index]
                                    
                                    NavigationLink(destination: CompressorView(asset: asset)) {
                                        VideoThumbnail(asset: asset)
                                        // Force square aspect ratio
                                            .aspectRatio(1, contentMode: .fit)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Fallback for no permission
                    VStack {
                        Image(systemName: "lock.slash")
                            .font(.largeTitle)
                            .padding()
                        Text("Please allow access to your Photo Library to compress videos.")
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Video")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
