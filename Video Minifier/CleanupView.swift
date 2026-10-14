//
//  CleanupView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import Photos
import SwiftUI
import UIKit

struct CleanupView: View {
    @StateObject private var viewModel = CleanupViewModel()
    @State private var previewItem: CleanupItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            content

            if viewModel.selectedCount > 0 {
                deleteBar
            }
        }
        .navigationTitle("Clean Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isScanning {
                    Button("Stop") { viewModel.cancelScan() }
                } else if viewModel.hasScanned {
                    Button("Rescan") { viewModel.startScan() }
                }
            }
        }
        .onAppear {
            viewModel.refreshPermission()
            if viewModel.hasPermission && !viewModel.hasScanned && !viewModel.isScanning {
                viewModel.startScan()
            }
        }
        .sheet(item: $previewItem) { item in
            AssetPreviewSheet(item: item, viewModel: viewModel)
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Couldn't delete", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasPermission {
            permissionPrompt
        } else if viewModel.isScanning && !viewModel.foundAnything {
            scanningState
        } else if viewModel.hasScanned && !viewModel.foundAnything && !viewModel.canLoadMore {
            emptyState
        } else {
            results
        }
    }

    // MARK: - States

    private var permissionPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Allow access to your Photos library to look for things worth deleting.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Allow Photo Access") { viewModel.requestAccess() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var scanningState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(viewModel.stageText)
                .font(.subheadline)
            Text("This reads your library on the device. Nothing is uploaded, and no iCloud copies are downloaded.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundColor(.green)
            Text("Nothing to clean up")
                .font(.headline)
            Text("No duplicates or QR codes in your library.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.ignoredCount > 0 {
                keptNotice
                    .padding(.top, 8)
            }
        }
        .padding(32)
    }

    // MARK: - Results

    private var results: some View {
        List {
            if !viewModel.duplicateGroups.isEmpty {
                ForEach(Array(viewModel.duplicateGroups.enumerated()), id: \.element.id) { index, group in
                    Section {
                        ForEach(group.items) { item in
                            row(for: item, note: item.id == group.items.first?.id ? "Keep" : nil)
                        }
                    } header: {
                        if index == 0 {
                            sectionHeader("Looks duplicated",
                                          detail: "\(viewModel.duplicateGroups.count) sets so far. The largest copy of each is kept. Tap to pick, hold to see one full size.")
                        } else {
                            Text("Set \(index + 1)")
                        }
                    }
                }
            }

            if !viewModel.qrItems.isEmpty {
                Section {
                    ForEach(viewModel.qrItems) { item in
                        row(for: item, note: nil)
                    }
                } header: {
                    sectionHeader("Contains a QR code",
                                  detail: "Usually one-time scans. Nothing can tell whether you still need one, so none are ticked.")
                }
            }

            if viewModel.canLoadMore {
                Section { loadMoreRow }
            }

            if viewModel.ignoredCount > 0 {
                Section { keptNotice }
            }

            // Room for the delete bar
            Section { Color.clear.frame(height: 56).listRowBackground(Color.clear) }
        }
        .listStyle(.insetGrouped)
    }

    /// Appearing is the trigger: this sits at the bottom of the list, so it
    /// only shows up once the user has scrolled that far.
    private var loadMoreRow: some View {
        HStack(spacing: 12) {
            if viewModel.isLoadingMore {
                ProgressView()
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isLoadingMore ? "Checking more photos…" : "Keep scrolling for more")
                    .font(.subheadline)
                Text("Checked \(viewModel.scannedCount) of \(viewModel.libraryCount) items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .onAppear { viewModel.loadMoreIfNeeded() }
    }

    /// Unticking is remembered, so there has to be a way back.
    private var keptNotice: some View {
        Button {
            viewModel.resetIgnored()
            viewModel.startScan()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(viewModel.ignoredCount) hidden — you chose to keep them",
                      systemImage: "eye.slash")
                    .font(.subheadline)
                Text("Unticking something keeps it out of later scans. Tap to bring them all back.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(nil)
        }
        .padding(.vertical, 4)
    }

    private func row(for item: CleanupItem, note: String?) -> some View {
        Button {
            viewModel.toggle(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.isSelected(item) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.isSelected(item) ? .red : .secondary)
                    .font(.title3)

                VideoThumbnail(asset: item.asset, showsDuration: item.isVideo)
                    .frame(width: 68, height: 68)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.sizeString)
                            .font(.subheadline)
                            .bold()
                        if let note = note {
                            Text(note)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                    Text(item.dateString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: item.isVideo ? "video" : "photo")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        // Simultaneous, so holding to preview does not swallow the tap
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                previewItem = item
            }
        )
    }

    // MARK: - Delete bar

    private var deleteBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await viewModel.deleteSelected() }
            } label: {
                Text("Delete \(viewModel.selectedCount) item\(viewModel.selectedCount == 1 ? "" : "s") · \(viewModel.selectedSizeString)")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Button("Clear selection") { viewModel.clearSelection() }
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }
}
