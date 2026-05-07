import SwiftUI

/// Main scan view with checklist
struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showingFolderPicker = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            CategorySidebar(selectedCategory: $viewModel.selectedCategory)
                .frame(minWidth: 180)
        } detail: {
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button(action: { showingFolderPicker = true }) {
                        Label("Scan Folder", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                    
                    if viewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning...")
                            .foregroundColor(.secondary)
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
                        // File list
                        FileListView(
                            item: viewModel.rootItem,
                            currentPath: viewModel.currentPath,
                            onNavigate: viewModel.navigateTo,
                            onSelect: viewModel.toggleSelection,
                            selectedItems: viewModel.selectedItems
                        )
                        
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
        .alert("Error", isPresented: $viewModel.hasError) {
            Button("OK") { viewModel.hasError = false }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

/// Category sidebar
struct CategorySidebar: View {
    @Binding var selectedCategory: Category?
    
    enum Category: String, CaseIterable {
        case all = "All"
        case apps = "Applications"
        case documents = "Documents"
        case downloads = "Downloads"
        case media = "Media"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .apps: return "app.badge"
            case .documents: return "doc.text"
            case .downloads: return "arrow.down.circle"
            case .media: return "play.circle"
            }
        }
    }
    
    var body: some View {
        List(selection: $selectedCategory) {
            ForEach(Category.allCases, id: \.self) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .tag(category)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Storage")
    }
}

/// File list with checkboxes
struct FileListView: View {
    let item: FileItem?
    let currentPath: [UUID]
    let onNavigate: (UUID) -> Void
    let onSelect: (FileItem) -> Void
    let selectedItems: Set<UUID>
    
    private var currentItem: FileItem? {
        guard let root = item else { return nil }
        // Navigate to current depth
        var current = root
        for id in currentPath {
            if let children = current.children {
                current = children.first { $0.id == id } ?? current
            }
        }
        return current
    }
    
    var body: some View {
        List {
            // Up button if not at root
            if !currentPath.isEmpty {
                Button(action: { onNavigate(UUID()) }) {  // Empty UUID signals "go up"
                    Label("Go Back", systemImage: "arrow.up")
                }
                .buttonStyle(.plain)
            }
            
            // Items
            if let current = currentItem, let children = current.children {
                ForEach(children) { child in
                    FileRowView(
                        item: child,
                        isSelected: selectedItems.contains(child.id),
                        onToggle: { onSelect(child) },
                        onNavigate: child.isDirectory ? { onNavigate(child.id) } : nil
                    )
                }
            }
        }
        .listStyle(.inset)
    }
}

/// Single file row with checkbox
struct FileRowView: View {
    let item: FileItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onNavigate: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Toggle(isSelected ? "✓" : "", isOn: .constant(isSelected))
                .toggleStyle(.checkbox)
                .onChange(of: isSelected) { _, _ in onToggle() }
            
            // Icon
            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(color(for: item.fileType))
                .frame(width: 20)
            
            // Name (clickable if directory)
            if item.isDirectory, let onNavigate = onNavigate {
                Button(action: onNavigate) {
                    Text(item.name)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(item.name)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Size
            Text(item.displaySize)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
    
    private func color(for type: FileType) -> Color {
        switch type {
        case .app: return .blue
        case .folder: return .orange
        case .document, .spreadsheet: return .green
        case .image, .video, .audio: return .pink
        case .code: return .cyan
        case .archive: return .purple
        default: return .gray
        }
    }
}

/// Delete footer bar
struct DeleteFooter: View {
    let selectedCount: Int
    let selectedSize: Int64
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(selectedCount) item\(selectedCount == 1 ? "" : "s") selected")
                    .font(.headline)
                Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedCount == 0)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

#Preview {
    ScanView()
}