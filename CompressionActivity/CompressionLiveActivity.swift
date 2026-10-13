//
//  CompressionLiveActivity.swift
//  CompressionActivity
//
//  Created by Muh Irsyad Ashari on 10/13/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct CompressionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompressionActivityAttributes.self) { context in
            // Lock screen and banner presentation
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.phase.symbolName)
                        .foregroundColor(tint(for: context.state.phase))
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percentText(context.state))
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.progress)
                            .tint(tint(for: context.state.phase))
                        HStack {
                            Text(context.attributes.videoName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if let eta = context.state.etaText {
                                Text(eta)
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase.symbolName)
                    .foregroundColor(tint(for: context.state.phase))
            } compactTrailing: {
                Text(percentText(context.state))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.phase.symbolName)
                    .foregroundColor(tint(for: context.state.phase))
            }
        }
    }

    private func percentText(_ state: CompressionActivityAttributes.ContentState) -> String {
        state.isFinished ? "" : "\(Int(state.progress * 100))%"
    }

    private func tint(for phase: CompressionActivityAttributes.Phase) -> Color {
        switch phase {
        case .done: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return .blue
        }
    }
}

private struct LockScreenView: View {
    let attributes: CompressionActivityAttributes
    let state: CompressionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: state.phase.symbolName)
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.statusText)
                        .font(.subheadline)
                        .bold()
                    Text(attributes.videoName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !state.isFinished {
                    Text("\(Int(state.progress * 100))%")
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                }
            }

            if !state.isFinished {
                ProgressView(value: state.progress)
                    .tint(tint)

                if let eta = state.etaText {
                    Text(eta)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private var tint: Color {
        switch state.phase {
        case .done: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return .blue
        }
    }
}
