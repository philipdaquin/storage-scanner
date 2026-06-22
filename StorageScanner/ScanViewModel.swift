import SwiftUI

/// View model for the scan view
@MainActor
class ScanViewModel: ObservableObject {
    @Published var rootItem: FileItem?
    @Published var currentPath: [UUID] = []  // Stack of folder IDs for navigation
    @Published var selectedItems: Set<UUID> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var selectedCategory: ScanCategory?
    @Published var hasError = false
    @Published var errorMessage = ""
    @Published var showDeleteConfirmation = false
    @Published var hasSuccess = false
    @Published var successMessage = ""
    @Published var viewMode: ScanViewMode = .list
    @Published var scanProgressText = ""
    @Published var scanFilesScanned = 0
    @Published var scanTotalSize: Int64 = 0
    @Published var isPreparingCategoryView = false
    
    private let scanner = FileScanner()
    private var lastScanRequest: ScanRequest?
    private var treeVersion = 0
    private var treeIndex = ScanTreeIndex(root: nil)
    private var treemapItemsCacheKey = ""
    private var treemapItemsCache: [FileItem] = []
    private var categoryDisplayTask: Task<Void, Never>?
    private var categoryPrewarmTask: Task<Void, Never>?
    private var categoryDisplayCache: [ScanCategory: CategoryDisplayCacheEntry] = [:]

    private enum ScanRequest {
        case single(URL)
        case group(name: String, urls: [URL])
    }

    private struct CategoryDisplayCacheEntry {
        let treeVersion: Int
        let item: FileItem
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

        guard let cache = categoryDisplayCache[selectedCategory],
              cache.treeVersion == treeVersion else {
            return nil
        }
        return cache.item
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

    var selectedDeletionItems: [FileItem] {
        treeIndex.topLevelSelectedItems(in: selectedItems)
            .filter { $0.isTrashable && $0.scanError == nil }
    }
    
    var selectedSize: Int64 {
        selectedDeletionItems.reduce(Int64(0)) { $0 + $1.size }
    }
    
    var selectedSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
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

        scan(url: URL(fileURLWithPath: "/", isDirectory: true))
    }

    func applyCategory(_ category: ScanCategory?) {
        selectedCategory = category
        currentPath = []
        invalidateDerivedCaches()
        refreshCategoryDisplayItemIfNeeded()
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
        categoryDisplayTask?.cancel()
        categoryPrewarmTask?.cancel()
        categoryDisplayTask = nil
        categoryPrewarmTask = nil
        categoryDisplayCache.removeAll()
        isPreparingCategoryView = false
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
                    self.categoryDisplayCache.removeAll()
                    self.invalidateDerivedCaches()
                    self.isScanning = false
                    self.hasScanned = true
                    self.scanProgressText = "Scan complete"
                    self.refreshCategoryDisplayItemIfNeeded()
                    self.prewarmCategoryDisplayItems()
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
    
    /// Request delete confirmation (shows review sheet)
    func deleteSelected() {
        guard !selectedItems.isEmpty else { return }
        showDeleteConfirmation = true
    }
    
    /// Confirm delete after reviewing the selected items
    func confirmDelete() {
        showDeleteConfirmation = false
        guard !selectedItems.isEmpty else { return }
        
        let fileManager = FileManager.default
        var deletedSize: Int64 = 0
        var errors: [String] = []
        let itemsToDelete = selectedDeletionItems
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
            applyDeletionToCurrentTree(deletedIDs: Set(itemsToDelete.map(\.id)))
        } else {
            errorMessage = errors.joined(separator: "\n")
            hasError = true
        }
        
        // Clear selections after updating the loaded tree in place.
        selectedItems = []
    }

    private func applyDeletionToCurrentTree(deletedIDs: Set<UUID>) {
        guard let rootItem else { return }

        guard let updatedRoot = pruningDeletedItems(from: rootItem, deletedIDs: deletedIDs) else {
            self.rootItem = nil
            self.treeIndex = ScanTreeIndex(root: nil)
            self.currentPath = []
            self.treeVersion += 1
            self.categoryDisplayCache.removeAll()
            self.categoryPrewarmTask?.cancel()
            self.categoryPrewarmTask = nil
            self.isPreparingCategoryView = false
            invalidateDerivedCaches()
            return
        }

        self.rootItem = updatedRoot
        self.treeIndex = ScanTreeIndex(root: updatedRoot)
        self.treeVersion += 1
        self.categoryDisplayCache.removeAll()
        self.categoryPrewarmTask?.cancel()
        self.categoryPrewarmTask = nil
        self.currentPath = trimmedCurrentPath()
        invalidateDerivedCaches()
        refreshCategoryDisplayItemIfNeeded()
        prewarmCategoryDisplayItems()
    }

    private func trimmedCurrentPath() -> [UUID] {
        guard !currentPath.isEmpty else { return [] }

        var path = currentPath
        while let last = path.last, treeIndex.item(for: last) == nil {
            path.removeLast()
        }
        return path
    }

    private func pruningDeletedItems(from item: FileItem, deletedIDs: Set<UUID>) -> FileItem? {
        if deletedIDs.contains(item.id) {
            return nil
        }

        guard item.isDirectory, let children = item.children else {
            return item
        }

        let updatedChildren = children.compactMap { pruningDeletedItems(from: $0, deletedIDs: deletedIDs) }
        var updatedItem = item
        updatedItem.children = updatedChildren
        updatedItem.size = updatedChildren.reduce(Int64(0)) { $0 + $1.size }
        return updatedItem
    }

    private func invalidateDerivedCaches() {
        treemapItemsCacheKey = ""
        treemapItemsCache = []
    }

    private func refreshCategoryDisplayItemIfNeeded() {
        categoryDisplayTask?.cancel()
        categoryDisplayTask = nil

        guard let rootItem,
              let selectedCategory,
              selectedCategory != .all else {
            isPreparingCategoryView = false
            return
        }

        if let cache = categoryDisplayCache[selectedCategory], cache.treeVersion == treeVersion {
            isPreparingCategoryView = false
            return
        }

        isPreparingCategoryView = true
        let rootSnapshot = rootItem
        let category = selectedCategory
        let version = treeVersion

        categoryDisplayTask = Task.detached(priority: .userInitiated) { [rootSnapshot, category, version] in
            let item = Self.buildCategoryDisplayItem(from: rootSnapshot, category: category)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.treeVersion == version, self.selectedCategory == category else { return }
                self.categoryDisplayCache[category] = CategoryDisplayCacheEntry(treeVersion: version, item: item)
                self.isPreparingCategoryView = false
                self.categoryDisplayTask = nil
            }
        }
    }

    private func prewarmCategoryDisplayItems() {
        categoryPrewarmTask?.cancel()
        categoryPrewarmTask = nil

        guard let rootItem else { return }

        let rootSnapshot = rootItem
        let version = treeVersion
        let categories = ScanCategory.allCases.filter { $0 != .all }

        categoryPrewarmTask = Task.detached(priority: .utility) { [rootSnapshot, version, categories] in
            var itemsByCategory: [ScanCategory: FileItem] = [:]

            for category in categories {
                guard !Task.isCancelled else { return }
                itemsByCategory[category] = Self.buildCategoryDisplayItem(from: rootSnapshot, category: category)
            }

            guard !Task.isCancelled else { return }
            let warmedItems = itemsByCategory

            await MainActor.run {
                guard self.treeVersion == version else { return }

                for (category, item) in warmedItems {
                    self.categoryDisplayCache[category] = CategoryDisplayCacheEntry(treeVersion: version, item: item)
                }

                if let selectedCategory = self.selectedCategory,
                   selectedCategory != .all,
                   self.categoryDisplayCache[selectedCategory]?.treeVersion == version {
                    self.isPreparingCategoryView = false
                }

                self.categoryPrewarmTask = nil
            }
        }
    }

    private nonisolated static func buildCategoryDisplayItem(from rootItem: FileItem, category: ScanCategory) -> FileItem {
        var matches: [FileItem] = []
        var stack: [FileItem] = [rootItem]

        while let current = stack.popLast() {
            if current.id != rootItem.id, category.matches(current) {
                matches.append(current)
            }

            if let children = current.children {
                for child in children.reversed() {
                    stack.append(child)
                }
            }
        }

        matches.sort {
            if $0.size == $1.size {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }

        let size = matches.reduce(Int64(0)) { $0 + $1.size }
        return FileItem(
            name: category.rawValue,
            path: rootItem.path,
            size: size,
            isDirectory: true,
            children: matches,
            isTrashable: false
        )
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
