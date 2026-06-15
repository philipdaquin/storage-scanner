import SwiftUI

struct ScanWorkspaceView: View {
    @ObservedObject var viewModel: ScanViewModel
    @Binding var showingFolderPicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { viewModel.scanDisk() }) {
                    Label("Scan Disk", systemImage: "internaldrive")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isScanning)

                Button(action: { showingFolderPicker = true }) {
                    Label("Scan Folder", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isScanning)

                if viewModel.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.scanProgressText.isEmpty ? "Scanning..." : viewModel.scanProgressText)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.scanFilesScanned) items, \(ByteCountFormatter.string(fromByteCount: viewModel.scanTotalSize, countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.hasScanned {
                    Picker("View", selection: $viewModel.viewMode) {
                        ForEach(ScanViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                Spacer()

                if viewModel.hasScanned {
                    Button(action: { viewModel.rescan() }) {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()

            Divider()

            if viewModel.hasScanned {
                VStack(spacing: 0) {
                    BreadcrumbBar(
                        items: viewModel.breadcrumbs,
                        onNavigate: viewModel.navigateToBreadcrumb
                    )
                    Divider()

                    if viewModel.viewMode == .list {
                        FileListView(
                            item: viewModel.displayedItem,
                            canNavigateUp: !viewModel.currentPath.isEmpty && (viewModel.selectedCategory == nil || viewModel.selectedCategory == .all),
                            onNavigate: viewModel.navigateTo,
                            onNavigateUp: viewModel.navigateUp,
                            onSelect: viewModel.toggleSelection,
                            selectedItems: viewModel.selectedItems
                        )
                    } else {
                        TreemapView(
                            items: viewModel.treemapItems,
                            selectedItems: viewModel.selectedItems,
                            onSelect: viewModel.toggleSelection
                        )
                    }

                    Divider()

                    DeleteFooter(
                        selectedCount: viewModel.selectedCount,
                        selectedSize: viewModel.selectedSize,
                        onDelete: viewModel.deleteSelected
                    )
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Select a folder to scan")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Click \"Scan Folder\" to analyze disk usage")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
