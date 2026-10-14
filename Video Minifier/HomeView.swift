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
    @EnvironmentObject private var queue: CompressionQueue

    @State private var showingFileImporter = false
    @State private var pickedFileURL: URL?
    @State private var navigateToFile = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
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

                    // MARK: - Clean Up
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Clean Up")
                            .font(.headline)

                        NavigationLink(destination: CleanupView()) {
                            MenuCard(title: "Review & Delete",
                                     subtitle: "Duplicates, QR code photos and large files",
                                     systemImage: "trash",
                                     color: .red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Video Minifier")
            .navigationBarTitleDisplayMode(.inline)
            // Pushes the compressor once a file is picked
            .navigationDestination(isPresented: $navigateToFile) {
                if let url = pickedFileURL {
                    CompressorView(fileURL: url)
                }
            }
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
    }

    // MARK: - Queue
    
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In Progress")
                .font(.headline)
            
            Button {
                queue.isShowingQueue = true
            } label: {
                InfoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(queue.isRunning || queue.isPaused
                                 ? queue.statusLine
                                 : (queue.lastSummary ?? "Queue finished"))
                                .font(.subheadline)
                                .bold()
                            Spacer()
                            if queue.isRunning || queue.isPaused {
                                Text("\(Int(queue.overallFraction * 100))%")
                                    .font(.subheadline)
                                    .monospacedDigit()
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if queue.isRunning || queue.isPaused {
                            ProgressView(value: queue.overallFraction)
                                .tint(queue.isPaused ? .orange : .blue)
                            if let job = queue.activeJob {
                                Text(job.name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Free Up Space")
                    .font(.headline)
                Spacer()
                if !largeVideos.videos.isEmpty {
                    NavigationLink(destination: BatchCompressView(largeVideos: largeVideos)) {
                        Text("Compress several")
                            .font(.subheadline)
                    }
                }
            }

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
                    ForEach(topVideos) { video in
                        NavigationLink(destination: CompressorView(asset: video.asset)) {
                            LargeVideoRow(video: video)
                        }
                        .buttonStyle(.plain)

                        if video.id != topVideos.last?.id {
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

    /// Only the worst offenders belong on the home screen; the rest are in
    /// the batch picker.
    private var topVideos: [LargeVideo] {
        Array(largeVideos.videos.prefix(5))
    }
    
    private var shownBytesString: String {
        let bytes = topVideos.reduce(Int64(0)) { $0 + $1.byteCount }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private var summaryText: String {
        let count = topVideos.count
        let extra = largeVideos.videos.count - count
        let tail = extra > 0 ? " \(extra) more are in Compress several." : ""
        
        if count == 1 {
            return "Your largest video uses \(shownBytesString). Compress it to get space back." + tail
        }
        return "Your \(count) largest videos use \(shownBytesString) in total." + tail
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
