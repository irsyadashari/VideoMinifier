//
//  CompressionQueueView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import SwiftUI

struct CompressionQueueView: View {
    @EnvironmentObject private var queue: CompressionQueue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if queue.isRunning || queue.isPaused {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(queue.statusLine)
                                .font(.subheadline)
                                .bold()
                            Spacer()
                            Text("\(Int(queue.overallFraction * 100))%")
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        ProgressView(value: queue.overallFraction)
                            .tint(queue.isPaused ? .orange : .blue)
                        Text("You can leave this screen. Leaving the app pauses the encoder — iOS won't run it in the background — and it continues from where it stopped.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let summary = queue.lastSummary {
                Section {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }

            Section {
                ForEach(queue.jobs) { job in
                    row(for: job)
                }
            } header: {
                Text(queue.jobs.isEmpty ? "Queue" : "\(queue.jobs.count) in queue")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if queue.isRunning || queue.isPaused {
                    Button("Cancel", role: .destructive) { queue.cancelAll() }
                } else if queue.jobs.contains(where: { $0.state.isFinished }) {
                    Button("Clear") { queue.removeFinished() }
                }
            }
        }
        .overlay {
            if queue.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Nothing queued")
                        .font(.headline)
                    Text("Pick videos from Free Up Space on the home screen.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            }
        }
    }

    private func row(for job: CompressionQueue.Job) -> some View {
        HStack(spacing: 12) {
            VideoThumbnail(asset: job.asset, showsDuration: true)
                .frame(width: 56, height: 56)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(job.state.label)
                    .font(.caption)
                    .foregroundColor(color(for: job.state))

                if !job.state.isFinished, job.state != .waiting {
                    ProgressView(value: job.state.fraction)
                        .tint(color(for: job.state))
                }
            }

            Spacer()

            icon(for: job.state)
        }
        .swipeActions {
            if job.state == .waiting || job.state.isFinished {
                Button("Remove", role: .destructive) { queue.remove(job) }
            }
        }
    }

    @ViewBuilder
    private func icon(for state: CompressionQueue.JobState) -> some View {
        switch state {
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .skipped:
            Image(systemName: "minus.circle").foregroundColor(.secondary)
        case .paused:
            Image(systemName: "pause.circle.fill").foregroundColor(.orange)
        case .waiting:
            Image(systemName: "clock").foregroundColor(.secondary)
        default:
            ProgressView()
        }
    }

    private func color(for state: CompressionQueue.JobState) -> Color {
        switch state {
        case .finished: return .green
        case .failed: return .red
        case .paused: return .orange
        case .skipped, .waiting: return .secondary
        default: return .blue
        }
    }
}
