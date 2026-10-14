//
//  AssetPreviewSheet.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import Photos
import SwiftUI

/// A full-size look at one photo or video, for deciding whether it can go.
struct AssetPreviewSheet: View {
    let item: CleanupItem
    @ObservedObject var viewModel: CleanupViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var downloadProgress: Double?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color.black

                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        VStack(spacing: 10) {
                            if failed {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title)
                                Text("Couldn't load this one.")
                                    .font(.caption)
                            } else {
                                ProgressView()
                                    .tint(.white)
                                if let progress = downloadProgress {
                                    Text("Downloading from iCloud… \(Int(progress * 100))%")
                                        .font(.caption)
                                }
                            }
                        }
                        .foregroundColor(.white.opacity(0.85))
                    }

                    if item.isVideo {
                        VStack {
                            Spacer()
                            HStack {
                                Label(durationText, systemImage: "video.fill")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.6))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                Spacer()
                            }
                            .padding(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                details
            }
            .ignoresSafeArea(edges: .horizontal)
            .navigationTitle(item.isVideo ? "Video" : "Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { load() }
    }

    // MARK: - Details

    private var details: some View {
        VStack(spacing: 14) {
            HStack {
                detail("Size", item.sizeString)
                Divider().frame(height: 28)
                detail("Dimensions", "\(item.asset.pixelWidth) × \(item.asset.pixelHeight)")
                Divider().frame(height: 28)
                detail("Taken", item.dateString.isEmpty ? "Unknown" : item.dateString)
            }

            Button {
                viewModel.toggle(item)
            } label: {
                let isMarked = viewModel.isSelected(item)
                Label(isMarked ? "Marked for deletion — keep it" : "Mark for deletion",
                      systemImage: isMarked ? "arrow.uturn.backward.circle" : "trash")
                    .font(.subheadline)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isMarked ? Color.secondary.opacity(0.15) : Color.red)
                    .foregroundColor(isMarked ? .primary : .white)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: item.asset.duration) ?? "0:00"
    }

    // MARK: - Loading

    /// Unlike the cleanup scan, this is an explicit request to look at one
    /// picture, so fetching an iCloud copy is what the user asked for.
    private func load() {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.progressHandler = { progress, _, _, _ in
            DispatchQueue.main.async {
                downloadProgress = progress < 1 ? progress : nil
            }
        }

        let target = CGSize(width: 1_200 * displayScale, height: 1_200 * displayScale)

        PHImageManager.default().requestImage(for: item.asset,
                                              targetSize: target,
                                              contentMode: .aspectFit,
                                              options: options) { result, info in
            DispatchQueue.main.async {
                if let result = result {
                    self.image = result
                    self.downloadProgress = nil
                } else if (info?[PHImageCancelledKey] as? Bool) != true {
                    self.failed = true
                }
            }
        }
    }
}
