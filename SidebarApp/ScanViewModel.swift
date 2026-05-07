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
    
    private let scanner = FileScanner()
    
    var selectedCount: Int {
        selectedItems.count
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
        isScanning = true
        hasScanned = false
        currentPath = []
        selectedItems = []
        rootItem = nil
        
        Task {
            do {
                let result = try await scanner.scan(url: url)
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
        if let root = rootItem {
            scan(url: root.path)
        }
    }
    
    /// Toggle selection of an item
    func toggleSelection(_ item: FileItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }
    
    /// Navigate into a folder
    func navigateTo(_ id: UUID) {
        if id == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
            // Go up
            if !currentPath.isEmpty {
                currentPath.removeLast()
            }
            return
        }
        
        // Find the folder and navigate into it
        if let root = rootItem {
            var current = root
            for pathId in currentPath {
                if let children = current.children {
                    current = children.first { $0.id == pathId } ?? current
                }
            }
            if let children = current.children, children.contains(where: { $0.id == id }) {
                currentPath.append(id)
            }
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
        let deletedNames: [String] = []
        
        // Collect all files to delete
        let itemsToDelete = collectSelectedItems(from: rootItem)
        let nameCount = itemsToDelete.count
        
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
        if let root = rootItem {
            scan(url: root.path)
        }
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
}