import Foundation

/// File item representing a file or directory in the scan
struct FileItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: URL
    var size: Int64  // bytes
    let isDirectory: Bool
    var children: [FileItem]?
    let modified: Date?
    
    // Selection state (not persisted in model)
    var isSelected: Bool = false
    
    init(name: String, path: URL, size: Int64 = 0, isDirectory: Bool = false, children: [FileItem]? = nil, modified: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.modified = modified
    }
    
    /// Human readable size string
    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// File type for color coding
    var fileType: FileType {
        let ext = (path.pathExtension.lowercased())
        if isDirectory {
            return .folder
        }
        switch ext {
        case "app": return .app
        case "dmg", "pkg", "zip", "tar", "gz", "rar", "7z": return .archive
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff": return .image
        case "mp4", "mov", "avi", "mkv", "wmv", "flv": return .video
        case "mp3", "wav", "aac", "flac", "m4a", "ogg": return .audio
        case "pdf", "doc", "docx", "txt", "rtf", "pages": return .document
        case "xls", "xlsx", "csv", "numbers": return .spreadsheet
        case "swift", "m", "h", "c", "cpp", "py", "js", "ts", "rs", "go", "zig": return .code
        case "json", "xml", "yaml", "yml", "toml": return .config
        case "md", "html", "css", "js": return .web
        default: return .other
        }
    }
}

enum FileType: String, CaseIterable {
    case app, archive, image, video, audio, document, spreadsheet, code, config, web, folder, other
    
    var color: String {
        switch self {
        case .app: return "blue"
        case .archive: return "purple"
        case .image: return "pink"
        case .video: return "red"
        case .audio: return "orange"
        case .document: return "green"
        case .spreadsheet: return "teal"
        case .code: return "cyan"
        case .config: return "yellow"
        case .web: return "indigo"
        case .folder: return "gray"
        case .other: return "gray"
        }
    }
}

/// Exclusion patterns (folders to skip by default)
let defaultExclusions: Set<String> = [
    ".git",
    "node_modules",
    ".DS_Store",
    "DerivedData",
    ".build",
    "target",
    "__pycache__",
    ".venv",
    "venv",
    ".cache",
    "Caches"
]

/// Async file scanner - scans directories and calculates sizes
actor FileScanner {
    private let fileManager = FileManager.default
    private var isCancelled = false
    private var progressHandler: ((ScanProgress) -> Void)?
    
    struct ScanProgress {
        let filesScanned: Int
        let currentPath: String
        let totalSize: Int64
    }
    
    /// Cancel ongoing scan
    func cancel() {
        isCancelled = true
    }
    
    /// Set progress handler
    func setProgressHandler(_ handler: @escaping (ScanProgress) -> Void) {
        progressHandler = handler
    }
    
    /// Scan a directory recursively
    func scan(url: URL, exclusions: Set<String> = defaultExclusions) async throws -> FileItem {
        isCancelled = false
        
        let root = try await scanDirectory(at: url, exclusions: exclusions, depth: 0)
        return root
    }
    
    private func scanDirectory(at url: URL, exclusions: Set<String>, depth: Int) async throws -> FileItem {
        if isCancelled {
            throw ScanError.cancelled
        }
        
        let resourceKeys: Set<URLResourceKey> = [
            .nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
        ]
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return FileItem(name: url.lastPathComponent, path: url, size: 0, isDirectory: true)
        }
        
        var children: [FileItem] = []
        var totalSize: Int64 = 0
        
        for itemURL in contents {
            let name = itemURL.lastPathComponent
            
            // Skip exclusions
            if exclusions.contains(name) {
                continue
            }
            
            let resourceValues = try? itemURL.resourceValues(forKeys: resourceKeys)
            let isDirectory = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let modified = resourceValues?.contentModificationDate
            
            if isDirectory {
                // Recurse into subdirectory
                let child = try await scanDirectory(at: itemURL, exclusions: exclusions, depth: depth + 1)
                totalSize += child.size
                children.append(child)
            } else {
                totalSize += size
                children.append(FileItem(
                    name: name,
                    path: itemURL,
                    size: size,
                    isDirectory: false,
                    modified: modified
                ))
            }
        }
        
        // Sort by size descending
        children.sort { $0.size > $1.size }
        
        return FileItem(
            name: url.lastPathComponent,
            path: url,
            size: totalSize,
            isDirectory: true,
            children: children
        )
    }
    
    enum ScanError: Error {
        case cancelled
    }
}