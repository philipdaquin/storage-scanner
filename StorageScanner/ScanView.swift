import SwiftUI

/// Main scan view with checklist
struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showingFolderPicker = false
    
    var body: some View {
        NavigationView {
            // Sidebar
            CategorySidebar(selectedCategory: $viewModel.selectedCategory)
                .frame(minWidth: 180)

            VStack(spacing: 0) {
                // Toolbar
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
                    // Checklist + Delete bar
                    VStack(spacing: 0) {
                        BreadcrumbBar(
                            items: viewModel.breadcrumbs,
                            onNavigate: viewModel.navigateToBreadcrumb
                        )
                        Divider()

                        // File list
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
                        
                        // Footer with total + delete
                        DeleteFooter(
                            selectedCount: viewModel.selectedCount,
                            selectedSize: viewModel.selectedSize,
                            onDelete: viewModel.deleteSelected
                        )
                    }
                } else {
                    // Empty state
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
        .frame(minWidth: 800, minHeight: 500)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.scan(url: url)
            }
        }
        .onChange(of: viewModel.selectedCategory) { category in
            viewModel.applyCategory(category)
        }
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK", role: .cancel) { viewModel.hasError = false }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Move to Trash?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            Text("Are you sure you want to move \(viewModel.selectedCount) item(s) (\(viewModel.selectedSizeFormatted)) to Trash?")
        }
        .alert("Done", isPresented: $viewModel.hasSuccess) {
            Button("OK") { viewModel.hasSuccess = false }
        } message: {
            Text(viewModel.successMessage)
        }
    }
}
