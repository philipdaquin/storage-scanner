import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// View model for the scan view
@MainActor
class ScanViewModel: ObservableObject {
    @Published var rootItem: FileItem?
    @Published var currentPath: [UUID] = []  // Stack of folder IDs for navigation
    @Published var selectedItems: Set<UUID> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var selectedCategory: CategorySidebar.Category?
    @Published var hasError = false
    @Published var errorMessage = ""
    @Published var showDeleteConfirmation = false
    @Published var hasSuccess = false
    @Published var successMessage = ""
    @Published var viewMode: ScanViewMode = .list
    
    private let scanner = FileScanner()
    private var lastScanRequest: ScanRequest?

    private enum ScanRequest {
        case single(URL)
        case group(name: String, urls: [URL])
    }
    
    var selectedCount: Int {
        selectedItems.count
    }

    var currentItem: FileItem? {
        item(for: currentPath)
    }

    var displayedItem: FileItem? {
        guard let currentItem else { return nil }
        guard let selectedCategory, selectedCategory != .all else {
            return currentItem
        }

        let matches = matchingItems(in: currentItem, category: selectedCategory)
        return FileItem(
            name: selectedCategory.rawValue,
            path: currentItem.path,
            size: matches.reduce(Int64(0)) { $0 + $1.size },
            isDirectory: true,
            children: matches,
            isTrashable: false
        )
    }

    var treemapItems: [FileItem] {
        guard let displayedItem else { return [] }
        return Array(largestRenderableItems(in: displayedItem).prefix(160))
    }

    var breadcrumbs: [FileItem] {
        guard var current = rootItem else { return [] }

        var items = [current]
        for id in currentPath {
            guard let next = current.children?.first(where: { $0.id == id }) else {
                break
            }
            items.append(next)
            current = next
        }
        return items
    }
    
    var selectedSize: Int64 {
        calculateSelectedSize(item: rootItem)
    }
    
    var selectedSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }
    
    private func calculateSelectedSize(item: FileItem?) -> Int64 {
        guard let item = item else { return 0 }
        
        var total: Int64 = 0
        if item.isDirectory, let children = item.children {
            for child in children {
                if selectedItems.contains(child.id) {
                    total += child.size
                } else {
                    total += calculateSelectedSize(item: child)
                }
            }
        }
        return total
    }
    
    /// Start scanning a folder
    func scan(url: URL) {
        lastScanRequest = .single(url)
        let accessURLs = [url]
        startScan {
            let scopedURLs = accessURLs.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            }
            return try await self.scanner.scan(url: url)
        }
    }

    func scanDisk() {
        selectedCategory = .all
        scan(url: URL(fileURLWithPath: "/", isDirectory: true))
    }

    func applyCategory(_ category: CategorySidebar.Category?) {
        selectedCategory = category
        currentPath = []

        if rootItem == nil, category == .all {
            scanDisk()
        }
    }

    private func startScan(_ scanOperation: @escaping () async throws -> FileItem) {
        isScanning = true
        hasScanned = false
        currentPath = []
        selectedItems = []
        rootItem = nil
        
        Task {
            do {
                let result = try await scanOperation()
                await MainActor.run {
                    self.rootItem = result
                    self.isScanning = false
                    self.hasScanned = true
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.hasError = true
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// Rescan current folder
    func rescan() {
        switch lastScanRequest {
        case .single(let url):
            scan(url: url)
        case .group(let name, let urls):
            lastScanRequest = .group(name: name, urls: urls)
            startScan {
                let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
                defer {
                    scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                }
                return try await self.scanner.scan(urls: urls, displayName: name)
            }
        case .none:
            if let root = rootItem {
                scan(url: root.path)
            }
        }
    }
    
    /// Toggle selection of an item
    func toggleSelection(_ item: FileItem) {
        guard item.isTrashable, item.scanError == nil else {
            hasError = true
            errorMessage = "\"\(item.name)\" cannot be moved to Trash from here. It may be protected by macOS permissions or be a system location."
            return
        }

        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }
    
    /// Navigate into a folder
    func navigateTo(_ id: UUID) {
        guard selectedCategory == nil || selectedCategory == .all,
              let current = currentItem,
              current.children?.contains(where: { $0.id == id && $0.isDirectory }) == true else {
            return
        }

        currentPath.append(id)
    }

    func navigateUp() {
        guard !currentPath.isEmpty else { return }
        currentPath.removeLast()
    }

    func navigateToBreadcrumb(_ item: FileItem) {
        guard item.id != rootItem?.id else {
            currentPath = []
            return
        }

        if let index = currentPath.firstIndex(of: item.id) {
            currentPath = Array(currentPath.prefix(through: index))
        }
    }
    
    /// Request delete confirmation (shows alert)
    func deleteSelected() {
        guard !selectedItems.isEmpty else { return }
        showDeleteConfirmation = true
    }
    
    /// Confirm delete after user clicks OK in alert
    func confirmDelete() {
        showDeleteConfirmation = false
        guard !selectedItems.isEmpty else { return }
        
        let fileManager = FileManager.default
        var deletedSize: Int64 = 0
        var errors: [String] = []
        // Collect all files to delete
        let itemsToDelete = collectSelectedItems(from: rootItem)
            .filter { $0.isTrashable && $0.scanError == nil }
        let nameCount = itemsToDelete.count

        guard !itemsToDelete.isEmpty else {
            hasError = true
            errorMessage = "No selected items can be moved to Trash. Protected system locations and restricted folders are skipped."
            selectedItems = []
            return
        }
        
        for item in itemsToDelete {
            do {
                try fileManager.trashItem(at: item.path, resultingItemURL: nil)
                deletedSize += item.size
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }
        
        if errors.isEmpty {
            let saved = ByteCountFormatter.string(fromByteCount: deletedSize, countStyle: .file)
            successMessage = "Moved \(nameCount) item(s) (\(saved)) to Trash."
            hasSuccess = true
        } else {
            errorMessage = errors.joined(separator: "\n")
            hasError = true
        }
        
        // Clear selections and rescan
        selectedItems = []
        rescan()
    }
    
    private func collectSelectedItems(from item: FileItem?) -> [FileItem] {
        guard let item = item else { return [] }
        
        var result: [FileItem] = []
        
        if selectedItems.contains(item.id) {
            result.append(item)
        } else if item.isDirectory, let children = item.children {
            for child in children {
                result.append(contentsOf: collectSelectedItems(from: child))
            }
        }
        
        return result
    }

    private func item(for path: [UUID]) -> FileItem? {
        guard var current = rootItem else { return nil }

        for id in path {
            guard let next = current.children?.first(where: { $0.id == id }) else {
                return current
            }
            current = next
        }

        return current
    }

    private func matchingItems(in item: FileItem, category: CategorySidebar.Category) -> [FileItem] {
        var matches: [FileItem] = []

        if item.id != rootItem?.id, category.matches(item) {
            matches.append(item)
        }

        for child in item.children ?? [] {
            matches.append(contentsOf: matchingItems(in: child, category: category))
        }

        matches.sort {
            if $0.size == $1.size {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }

        return matches
    }

    private func largestRenderableItems(in item: FileItem) -> [FileItem] {
        var items: [FileItem] = []

        func collect(_ node: FileItem) {
            guard node.size > 0, node.scanError == nil else { return }

            if node.children?.isEmpty != false || node.fileType == .app {
                items.append(node)
                return
            }

            node.children?.forEach(collect)
        }

        item.children?.forEach(collect)

        return items.sorted {
            if $0.size == $1.size {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }
    }
}

enum ScanViewMode: String, CaseIterable, Identifiable {
    case list = "List"
    case map = "Map"

    var id: String { rawValue }
}

extension CategorySidebar.Category {
    func matches(_ item: FileItem) -> Bool {
        switch self {
        case .all:
            return true
        case .apps:
            return item.fileType == .app || item.path.path.contains("/Applications/")
        case .documents:
            return [.document, .spreadsheet, .pdfLike].contains(item.categoryKind)
        case .downloads:
            return item.path.path.contains("/Downloads/")
        case .media:
            return [.image, .video, .audio].contains(item.fileType)
        }
    }
}

private enum FileCategoryKind {
    case document
    case spreadsheet
    case pdfLike
    case other
}

private extension FileItem {
    var categoryKind: FileCategoryKind {
        switch fileType {
        case .document:
            return path.pathExtension.lowercased() == "pdf" ? .pdfLike : .document
        case .spreadsheet:
            return .spreadsheet
        default:
            return .other
        }
    }
}
