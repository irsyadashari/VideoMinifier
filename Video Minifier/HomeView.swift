//
//  HomeView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/13/26.
//

import SwiftUI
import Photos
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var largeVideos = LargeVideosViewModel()

    @State private var showingFileImporter = false
    @State private var pickedFileURL: URL?
    @State private var navigateToFile = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // MARK: - Pick a Source
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Compress a Video")
                            .font(.headline)

                        // Photos -> existing library browser
                        NavigationLink(destination: VideoBrowserView()) {
                            MenuCard(title: "Photos",
                                     subtitle: "Pick a video from your Photos library",
                                     systemImage: "photo.on.rectangle",
                                     color: .blue)
                        }
                        .buttonStyle(.plain)

                        // Files -> document picker
                        Button(action: { showingFileImporter = true }) {
                            MenuCard(title: "Files",
                                     subtitle: "Pick a video from the Files app",
                                     systemImage: "folder",
                                     color: .orange)
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: - Storage Suggestions
                    suggestionsSection
                }
                .padding()
            }
            .navigationTitle("Video Minifier")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                // Hidden link that pushes the compressor once a file is picked
                NavigationLink(isActive: $navigateToFile) {
                    if let url = pickedFileURL {
                        CompressorView(fileURL: url)
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            )
            .onAppear {
                largeVideos.refreshIfNeeded()
            }
            .fileImporter(isPresented: $showingFileImporter,
                          allowedContentTypes: [.movie, .video],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        pickedFileURL = url
                        navigateToFile = true
                    }
                case .failure(let error):
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Free Up Space")
                .font(.headline)

            if !largeVideos.hasPermission {
                InfoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Allow access to your Photos library to see which videos take up the most space.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Allow Photo Access") {
                            largeVideos.requestAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if largeVideos.isScanning && largeVideos.videos.isEmpty {
                InfoCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking your library…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else if largeVideos.videos.isEmpty {
                InfoCard {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No videos over \(largeVideos.thresholdString). Nothing to clean up.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(largeVideos.videos) { video in
                        NavigationLink(destination: CompressorView(asset: video.asset)) {
                            LargeVideoRow(video: video)
                        }
                        .buttonStyle(.plain)

                        if video.id != largeVideos.videos.last?.id {
                            Divider().padding(.leading, 80)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                // While rescanning, these rows may name a video that was just
                // deleted, so cover them rather than let one be tapped again.
                .overlay(
                    Group {
                        if largeVideos.isScanning {
                            ZStack {
                                Color(.secondarySystemBackground).opacity(0.95)
                                VStack(spacing: 8) {
                                    ProgressView()
                                    Text("Updating library…")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .cornerRadius(16)
                        }
                    }
                )
                .allowsHitTesting(!largeVideos.isScanning)
                .animation(.easeInOut(duration: 0.15), value: largeVideos.isScanning)
            }
        }
    }

    private var summaryText: String {
        let count = largeVideos.videos.count
        if count == 1 {
            return "Your largest video uses \(largeVideos.totalSizeString). Compress it to get space back."
        }
        return "Your \(count) largest videos use \(largeVideos.totalSizeString) in total. Compress one to get space back."
    }
}

// MARK: - Components

private struct MenuCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(color)
                .cornerRadius(14)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

private struct LargeVideoRow: View {
    let video: LargeVideo

    var body: some View {
        HStack(spacing: 12) {
            VideoThumbnail(asset: video.asset, showsDuration: false)
                .frame(width: 56, height: 56)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(video.sizeString)
                .font(.subheadline)
                .bold()
                .foregroundColor(.orange)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private var subtitleText: String {
        var parts: [String] = []
        if let duration = Self.durationFormatter.string(from: video.asset.duration) {
            parts.append(duration)
        }
        if let date = video.asset.creationDate {
            parts.append(Self.dateFormatter.string(from: date))
        }
        return parts.joined(separator: " · ")
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct InfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
    }
}
