//
//  CleanupView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import Photos
import SwiftUI

struct CleanupView: View {
    @StateObject private var viewModel = CleanupViewModel()
    @State private var previewItem: CleanupItem?

    var body: some View {
        content
        .safeAreaInset(edge: .bottom) {
            if viewModel.selectedCount > 0 {
                deleteBar
            }
        }
        .queuePill()
        .navigationTitle("Clean Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isScanning {
                    Button("Stop") { viewModel.stopScanning() }
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
                            row(for: item, note: item.id == group.items.first?.id ? "Largest" : nil)
                        }
                    } header: {
                        if index == 0 {
                            sectionHeader("Looks duplicated",
                                          detail: "\(viewModel.duplicateGroups.count) sets so far. Nothing is ticked for you — tap to pick, hold for a bigger look, swipe for Keep.")
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
                                  detail: "Usually one-time scans. Nothing can tell whether you still need one, so have a look before ticking.")
                }
            }

            if viewModel.canLoadMore {
                Section { loadMoreRow }
            }

            if viewModel.ignoredCount > 0 {
                Section { keptNotice }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Tapping once works through the library until it finds something. The
    /// counter shows it moving and Stop gets out, so there is no reason to
    /// hand the user a button to keep pressing.
    private var loadMoreRow: some View {
        HStack(spacing: 12) {
            if viewModel.isLoadingMore {
                ProgressView()
            } else {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.isLoadingMore ? "Looking through your photos…" : "Check more photos")
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(viewModel.isLoadingMore ? .primary : .blue)
                Text("Checked \(viewModel.scannedCount) of \(viewModel.libraryCount) items")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                if viewModel.isLoadingMore {
                    ProgressView(value: viewModel.progress)
                        .frame(maxWidth: 160)
                }
            }
            
            Spacer()
            
            if viewModel.isLoadingMore {
                Button("Stop") { viewModel.stopScanning() }
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !viewModel.isLoadingMore {
                viewModel.loadMoreIfNeeded()
            }
        }
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
                Text("Swiping a row and choosing Keep takes it out of later scans. Tap to bring them all back.")
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
            // One simple hit area for the whole row, rather than one per
            // subview, so a drag anywhere on it reaches the list
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                previewItem = item
            } label: {
                Label("Open preview", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                viewModel.keep(item)
            } label: {
                Label("Keep — hide from scans", systemImage: "eye.slash")
            }
        } preview: {
            VideoThumbnail(asset: item.asset, showsDuration: item.isVideo)
                .frame(width: 280, height: 280)
        }
        .swipeActions(edge: .trailing) {
            Button {
                viewModel.keep(item)
            } label: {
                Label("Keep", systemImage: "eye.slash")
            }
            .tint(.green)
        }
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
