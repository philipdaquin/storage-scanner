import SwiftUI

/// Breadcrumb navigation for the scanned tree
struct BreadcrumbBar: View {
    let items: [FileItem]
    let onNavigate: (FileItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: { onNavigate(item) }) {
                        Label(item.name.isEmpty ? item.path.path : item.name, systemImage: index == 0 ? "externaldrive" : "folder")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(index == items.count - 1 ? .primary : .accentColor)
                    .disabled(index == items.count - 1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Category sidebar
struct CategorySidebar: View {
    @Binding var selectedCategory: ScanCategory?

    var body: some View {
        List(selection: $selectedCategory) {
            ForEach(ScanCategory.allCases) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .tag(category)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Storage")
    }
}

struct TreemapView: View {
    let items: [FileItem]
    let selectedItems: Set<UUID>
    let onSelect: (FileItem) -> Void

    var body: some View {
        GeometryReader { geometry in
            let rectangles = TreemapLayout.rectangles(
                for: items,
                in: CGRect(origin: .zero, size: geometry.size)
            )

            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)

                ForEach(rectangles) { tile in
                    TreemapTile(
                        tile: tile,
                        isSelected: selectedItems.contains(tile.item.id),
                        onSelect: { onSelect(tile.item) }
                    )
                }
            }
        }
        .padding(10)
    }
}

struct TreemapTile: View {
    let tile: TreemapTileModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(color(for: tile.item.fileType).opacity(isSelected ? 0.95 : 0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isSelected ? Color.primary : Color.white.opacity(0.35), lineWidth: isSelected ? 3 : 1)
                    )

                if tile.frame.width > 92 && tile.frame.height > 44 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tile.item.name)
                            .font(.system(size: min(13, max(9, tile.frame.height / 7)), weight: .semibold))
                            .lineLimit(2)
                        Text(tile.item.displaySize)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .opacity(0.78)
                    }
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .padding(7)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: max(0, tile.frame.width - 2), height: max(0, tile.frame.height - 2))
        .position(x: tile.frame.midX, y: tile.frame.midY)
        .help("\(tile.item.path.path)\n\(tile.item.displaySize)")
        .disabled(!tile.item.isTrashable || tile.item.scanError != nil)
    }

    private func color(for type: FileType) -> Color {
        switch type {
        case .app: return Color(red: 0.20, green: 0.43, blue: 0.95)
        case .archive: return Color(red: 0.55, green: 0.32, blue: 0.75)
        case .image: return Color(red: 0.86, green: 0.24, blue: 0.45)
        case .video: return Color(red: 0.82, green: 0.23, blue: 0.20)
        case .audio: return Color(red: 0.88, green: 0.49, blue: 0.13)
        case .document, .spreadsheet: return Color(red: 0.17, green: 0.55, blue: 0.34)
        case .code, .config, .web: return Color(red: 0.13, green: 0.55, blue: 0.67)
        case .folder: return Color(red: 0.45, green: 0.47, blue: 0.50)
        case .error: return .red
        case .other: return Color(red: 0.36, green: 0.39, blue: 0.43)
        }
    }
}

/// File list with checkboxes
struct FileListView: View {
    let item: FileItem?
    let canNavigateUp: Bool
    let onNavigate: (UUID) -> Void
    let onNavigateUp: () -> Void
    let onSelect: (FileItem) -> Void
    let selectedItems: Set<UUID>

    var body: some View {
        List {
            if canNavigateUp {
                Button(action: onNavigateUp) {
                    Label("Go Back", systemImage: "arrow.up")
                }
                .buttonStyle(.plain)
            }

            if let current = item, let children = current.children {
                ForEach(children) { child in
                    FileRowView(
                        item: child,
                        isSelected: selectedItems.contains(child.id),
                        onToggle: { onSelect(child) },
                        onNavigate: child.isDirectory && child.scanError == nil ? { onNavigate(child.id) } : nil
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
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { newValue in
                    if newValue != isSelected {
                        onToggle()
                    }
                }
            ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!item.isTrashable || item.scanError != nil)

            Image(systemName: iconName)
                .foregroundColor(color(for: item.fileType))
                .frame(width: 20)

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

            Text(item.displaySize)
                .foregroundColor(.secondary)
                .monospacedDigit()

            if let scanError = item.scanError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .help(scanError)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if item.scanError != nil {
            return "exclamationmark.triangle.fill"
        }
        return item.isDirectory ? "folder.fill" : "doc"
    }

    private func color(for type: FileType) -> Color {
        switch type {
        case .app: return .blue
        case .folder: return .orange
        case .document, .spreadsheet: return .green
        case .image, .video, .audio: return .pink
        case .code: return .cyan
        case .archive: return .purple
        case .error: return .red
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
                Text("\(selectedCount) item(s) selected")
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
