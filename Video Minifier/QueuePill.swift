//
//  QueuePill.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import SwiftUI

/// The running-queue pill, attached as a bottom safe-area inset so the screen
/// underneath genuinely gives up the space rather than being covered.
///
/// It has to be applied per screen, outside any bar that screen already has:
/// an inset placed outside a NavigationStack does not reach the scroll view
/// inside it, which is how it ended up sitting on top of the content.
struct QueuePillModifier: ViewModifier {
    @EnvironmentObject private var queue: CompressionQueue

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if queue.isRunning || queue.isPaused {
                    pill
                        .padding(.horizontal)
                        .padding(.top, 6)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: queue.isRunning)
            .animation(.easeInOut(duration: 0.2), value: queue.isPaused)
    }

    private var pill: some View {
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

extension View {
    /// Adds the queue pill below this screen's own content and bars.
    func queuePill() -> some View {
        modifier(QueuePillModifier())
    }
}
