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
    @Published var scanProgressText = ""
    @Published var scanFilesScanned = 0
    @Published var scanTotalSize: Int64 = 0
    
    private let scanner = FileScanner()
    private var lastScanRequest: ScanRequest?
    private var suppressNextCategoryScan = false
    private var treeVersion = 0
    private var treeIndex = ScanTreeIndex(root: nil)
    private var displayedItemCacheKey = ""
    private var displayedItemCache: FileItem?
    private var treemapItemsCacheKey = ""
    private var treemapItemsCache: [FileItem] = []

    private enum ScanRequest {
        case single(URL)
        case group(name: String, urls: [URL])
    }
    
    var selectedCount: Int {
        selectedItems.count
    }

    var currentItem: FileItem? {
        if currentPath.isEmpty {
            return rootItem
        }

        guard let currentID = currentPath.last else {
            return rootItem
        }

        return treeIndex.item(for: currentID) ?? rootItem
    }

    var displayedItem: FileItem? {
        guard let currentItem else { return nil }
        guard let selectedCategory, selectedCategory != .all else {
            return currentItem
        }

        let key = "\(pathCacheKey())|\(selectedCategory.rawValue)"
        if displayedItemCacheKey == key {
            return displayedItemCache
        }

        let matches = treeIndex.matchingDescendants(of: currentItem.id) {
            selectedCategory.matches($0)
        }
        let item = FileItem(
            name: selectedCategory.rawValue,
            path: currentItem.path,
            size: matches.reduce(Int64(0)) { $0 + $1.size },
            isDirectory: true,
            children: matches,
            isTrashable: false
        )
        displayedItemCacheKey = key
        displayedItemCache = item
        return item
    }

    var treemapItems: [FileItem] {
        guard let displayedItem else { return [] }

        let key = "\(pathCacheKey())|\(selectedCategory?.rawValue ?? "all")|\(displayedItem.id.uuidString)"
        if treemapItemsCacheKey == key {
            return treemapItemsCache
        }

        let items = directRenderableChildren(of: displayedItem, limit: 160)
        treemapItemsCacheKey = key
        treemapItemsCache = items
        return items
    }

    var breadcrumbs: [FileItem] {
        treeIndex.breadcrumbPath(for: currentPath)
    }
    
    var selectedSize: Int64 {
        guard !selectedItems.isEmpty else { return 0 }
        guard let rootID = treeIndex.rootID else { return 0 }
        return calculateSelectedSize(from: rootID)
    }
    
    var selectedSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }
    
    private func calculateSelectedSize(from rootID: UUID) -> Int64 {
        guard let rootNode = treeIndex.node(for: rootID) else { return 0 }

        var total: Int64 = 0
        var stack = [rootNode.item]

        while let item = stack.popLast() {
            if selectedItems.contains(item.id) {
                total += item.size
                continue
            }

            guard item.isDirectory, let children = item.children else { continue }
            stack.append(contentsOf: children)
        }

        return total
    }
    
    /// Start scanning a folder
    func scan(url: URL) {
        guard !isScanning else { return }

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
        guard !isScanning else { return }

        if selectedCategory != .all {
            suppressNextCategoryScan = true
            selectedCategory = .all
        } else {
            suppressNextCategoryScan = false
        }
        scan(url: URL(fileURLWithPath: "/", isDirectory: true))
    }

    func applyCategory(_ category: CategorySidebar.Category?) {
        selectedCategory = category
        currentPath = []
        invalidateDerivedCaches()

        if suppressNextCategoryScan, category == .all {
            suppressNextCategoryScan = false
            return
        }
        suppressNextCategoryScan = false

        if !isScanning, rootItem == nil, category == .all {
            scanDisk()
        }
    }

    private func startScan(_ scanOperation: @escaping () async throws -> FileItem) {
        isScanning = true
        hasScanned = false
        hasError = false
        errorMessage = ""
        scanProgressText = "Starting scan..."
        scanFilesScanned = 0
        scanTotalSize = 0
        currentPath = []
        selectedItems = []
        rootItem = nil
        treeIndex = ScanTreeIndex(root: nil)
        invalidateDerivedCaches()
        
        Task {
            await self.scanner.setProgressHandler { [weak self] progress in
                Task { @MainActor in
                    self?.scanFilesScanned = progress.filesScanned
                    self?.scanTotalSize = progress.totalSize
                    self?.scanProgressText = "Scanning \(progress.currentPath)"
                }
            }

            do {
                let result = try await scanOperation()
                await MainActor.run {
                    self.rootItem = result
                    self.treeIndex = ScanTreeIndex(root: result)
                    self.treeVersion += 1
                    self.invalidateDerivedCaches()
                    self.isScanning = false
                    self.hasScanned = true
                    self.scanProgressText = "Scan complete"
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.hasError = true
                    self.errorMessage = error.localizedDescription
                    self.scanProgressText = ""
                }
            }

            await self.scanner.setProgressHandler { _ in }
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
              let currentNode = treeIndex.node(for: current.id),
              currentNode.childIDs.contains(id),
              treeIndex.item(for: id)?.isDirectory == true else {
            return
        }

        currentPath.append(id)
        invalidateDerivedCaches()
    }

    func navigateUp() {
        guard !currentPath.isEmpty else { return }
        currentPath.removeLast()
        invalidateDerivedCaches()
    }

    func navigateToBreadcrumb(_ item: FileItem) {
        guard item.id != rootItem?.id else {
            currentPath = []
            invalidateDerivedCaches()
            return
        }

        if let index = currentPath.firstIndex(of: item.id) {
            currentPath = Array(currentPath.prefix(through: index))
            invalidateDerivedCaches()
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
        let itemsToDelete = collectSelectedItems(from: treeIndex.rootID)
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
    
    private func collectSelectedItems(from rootID: UUID?) -> [FileItem] {
        guard let rootID, let rootNode = treeIndex.node(for: rootID) else { return [] }

        var result: [FileItem] = []
        var stack = [rootNode.item]

        while let item = stack.popLast() {
            if selectedItems.contains(item.id) {
                result.append(item)
                continue
            }

            guard item.isDirectory, let children = item.children else { continue }
            stack.append(contentsOf: children)
        }

        return result
    }

    private func invalidateDerivedCaches() {
        displayedItemCacheKey = ""
        displayedItemCache = nil
        treemapItemsCacheKey = ""
        treemapItemsCache = []
    }

    private func pathCacheKey() -> String {
        let path = currentPath.map(\.uuidString).joined(separator: "/")
        return "\(treeVersion)|\(path)"
    }

    private func directRenderableChildren(of item: FileItem, limit: Int) -> [FileItem] {
        guard let children = item.children else { return [] }

        return children
            .filter { $0.size > 0 && $0.scanError == nil }
            .sorted {
            if $0.size == $1.size {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
            }
            .prefix(limit)
            .map { $0 }
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
