//
//  BatchCompressView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import SwiftUI

/// Pick several videos, choose how they are compressed, and hand them to the
/// queue. Everything after that happens in the background.
struct BatchCompressView: View {
    @ObservedObject var largeVideos: LargeVideosViewModel
    @EnvironmentObject private var queue: CompressionQueue

    @State private var selection: Set<String> = []

    /// Anything already handed to the queue is no longer a choice to make here.
    private var available: [LargeVideo] {
        largeVideos.videos.filter { video in
            !queue.jobs.contains { $0.id == video.id }
        }
    }

    private var selectedVideos: [LargeVideo] {
        available.filter { selection.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedVideos.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Section {
                    Picker("Quality", selection: $queue.quality) {
                        ForEach(QualityOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Originals", selection: $queue.policy) {
                        ForEach(CompressionQueue.OriginalPolicy.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(queue.policy.explanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Settings for the whole batch")
                }

                Section {
                    if available.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Everything is already queued")
                                .font(.subheadline)
                                .bold()
                            Text("Clear finished jobs in the queue to see them here again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(available) { video in
                            row(for: video)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(available.count) video\(available.count == 1 ? "" : "s")")
                        Spacer()
                        if !available.isEmpty {
                            Button(selection.count == available.count ? "Deselect all" : "Select all") {
                                if selection.count == available.count {
                                    selection = []
                                } else {
                                    selection = Set(available.map(\.id))
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }

                Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
            }
            .listStyle(.insetGrouped)

            if !selection.isEmpty {
                startBar
            }
        }
        .navigationTitle("Compress Several")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for video: LargeVideo) -> some View {
        Button {
            if selection.contains(video.id) {
                selection.remove(video.id)
            } else {
                selection.insert(video.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selection.contains(video.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selection.contains(video.id) ? .blue : .secondary)
                    .font(.title3)

                VideoThumbnail(asset: video.asset, showsDuration: true)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(video.sizeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var startBar: some View {
        VStack(spacing: 6) {
            Button {
                queue.enqueue(selectedVideos)
                queue.start()
                selection = []
                queue.isShowingQueue = true
            } label: {
                Text("Compress \(selection.count) video\(selection.count == 1 ? "" : "s")")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Text("\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)) selected · runs in the background while you use the app")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }
}
