//
//  RootView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import SwiftUI

/// Wraps the app so the queue can be reopened from anywhere. The pill sits
/// above whatever screen is showing, and the queue itself is presented as a
/// sheet rather than pushed, so closing it never loses the way back.
struct RootView: View {
    @EnvironmentObject private var queue: CompressionQueue

    var body: some View {
        HomeView()
            .overlay(alignment: .bottom) {
                if queue.isRunning || queue.isPaused {
                    progressPill
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: queue.isRunning)
            .sheet(isPresented: $queue.isShowingQueue) {
                NavigationStack {
                    CompressionQueueView()
                }
            }
    }

    private var progressPill: some View {
        Button {
            queue.isShowingQueue = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: queue.isPaused ? "pause.circle.fill" : "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundColor(queue.isPaused ? .orange : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(queue.statusLine)
                            .font(.subheadline)
                            .bold()
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(queue.overallFraction * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: queue.overallFraction)
                        .tint(queue.isPaused ? .orange : .blue)
                }

                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}
