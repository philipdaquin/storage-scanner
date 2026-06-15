import Darwin
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
    let scanError: String?
    let isTrashable: Bool
    
    // Selection state (not persisted in model)
    var isSelected: Bool = false
    
    init(name: String, path: URL, size: Int64 = 0, isDirectory: Bool = false, children: [FileItem]? = nil, modified: Date? = nil, scanError: String? = nil, isTrashable: Bool = true) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.modified = modified
        self.scanError = scanError
        self.isTrashable = isTrashable
    }
    
    /// Human readable size string
    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// File type for color coding
    var fileType: FileType {
        if scanError != nil {
            return .error
        }

        let ext = (path.pathExtension.lowercased())
        if ext == "app" {
            return .app
        }
        if isDirectory {
            return .folder
        }
        switch ext {
        case "dmg", "pkg", "zip", "tar", "gz", "rar", "7z": return .archive
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff": return .image
        case "mp4", "mov", "avi", "mkv", "wmv", "flv": return .video
        case "mp3", "wav", "aac", "flac", "m4a", "ogg": return .audio
        case "pdf", "doc", "docx", "txt", "rtf", "pages": return .document
        case "xls", "xlsx", "csv", "numbers": return .spreadsheet
        case "swift", "m", "h", "c", "cpp", "py", "ts", "rs", "go", "zig": return .code
        case "json", "xml", "yaml", "yml", "toml": return .config
        case "md", "html", "css", "js": return .web
        default: return .other
        }
    }
}

enum FileType: String, CaseIterable {
    case app, archive, image, video, audio, document, spreadsheet, code, config, web, folder, error, other
    
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
        case .error: return "red"
        case .folder: return "gray"
        case .other: return "gray"
        }
    }
}

/// Exclusion patterns skipped before stat/recursion, following ncdu's traversal order.
let defaultExclusions: [String] = [
    ".git/",
    "node_modules/",
    ".DS_Store",
    "DerivedData/",
    ".build/",
    "target/",
    "__pycache__/",
    ".venv/",
    "venv/",
    ".cache/",
    "Caches/"
]

private struct ExclusionPattern {
    let rawValue: String
    let directoryOnly: Bool
    let anchored: Bool
    let pattern: String
    let containsSlash: Bool

    init(_ value: String) {
        rawValue = value
        directoryOnly = value.hasSuffix("/")
        anchored = value.hasPrefix("/")

        var normalized = value
        if directoryOnly {
            normalized.removeLast()
        }
        if anchored {
            normalized.removeFirst()
        }
        pattern = normalized
        containsSlash = normalized.contains("/")
    }

    func matches(name: String, relativePath: String, absolutePath: String, isDirectory: Bool) -> Bool {
        guard !directoryOnly || isDirectory else {
            return false
        }

        let valueToMatch: String
        if anchored {
            valueToMatch = absolutePath
        } else if containsSlash {
            valueToMatch = relativePath
        } else {
            valueToMatch = name
        }

        return fnmatch(pattern, valueToMatch, 0) == 0
    }
}

/// Async file scanner - scans directories and calculates sizes
actor FileScanner {
    private let fileManager = FileManager.default
    private var isCancelled = false
    private var progressHandler: ((ScanProgress) -> Void)?
    private var filesScanned = 0
    private var totalSizeScanned: Int64 = 0
    private var lastProgressUpdate = Date.distantPast
    
    struct ScanProgress: Sendable {
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
    func scan(url: URL, exclusions: [String] = defaultExclusions) async throws -> FileItem {
        isCancelled = false
        filesScanned = 0
        totalSizeScanned = 0
        lastProgressUpdate = .distantPast

        let patterns = exclusions.map(ExclusionPattern.init)
        let root = try await scanDirectory(
            at: url,
            relativePath: "",
            exclusions: patterns
        )
        return root
    }

    func scan(urls: [URL], displayName: String, exclusions: [String] = defaultExclusions) async throws -> FileItem {
        isCancelled = false
        filesScanned = 0
        totalSizeScanned = 0
        lastProgressUpdate = .distantPast

        let patterns = exclusions.map(ExclusionPattern.init)
        var children: [FileItem] = []
        var totalSize: Int64 = 0

        for url in urls {
            let child = try await scanDirectory(
                at: url,
                relativePath: url.lastPathComponent,
                exclusions: patterns
            )
            totalSize += child.size
            children.append(child)
        }

        children.sort(by: sortBySizeThenName)

        return FileItem(
                name: displayName,
                path: FileManager.default.homeDirectoryForCurrentUser,
                size: totalSize,
                isDirectory: true,
                children: children,
                isTrashable: false
            )
    }

    private func scanDirectory(at url: URL, relativePath: String, exclusions: [ExclusionPattern]) async throws -> FileItem {
        if isCancelled {
            throw ScanError.cancelled
        }
        
        let resourceKeys: Set<URLResourceKey> = [
            .nameKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]

        let directoryValues = try? url.resourceValues(forKeys: resourceKeys)
        let directoryOwnSize = allocatedSize(from: directoryValues)
        filesScanned += 1
        totalSizeScanned += directoryOwnSize
        reportProgress(currentPath: url.path)

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            )
        } catch {
            return FileItem(
                name: displayName(for: url),
                path: url,
                size: directoryOwnSize,
                isDirectory: true,
                children: [],
                modified: directoryValues?.contentModificationDate,
                scanError: error.localizedDescription,
                isTrashable: false
            )
        }
        
        var children: [FileItem] = []
        var totalSize = directoryOwnSize
        
        for itemURL in contents {
            let name = itemURL.lastPathComponent
            let resourceValues = try? itemURL.resourceValues(forKeys: resourceKeys)
            let isDirectory = resourceValues?.isDirectory ?? false
            let isSymbolicLink = resourceValues?.isSymbolicLink ?? false
            let childRelativePath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
            let childAbsolutePath = itemURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if exclusions.contains(where: { $0.matches(name: name, relativePath: childRelativePath, absolutePath: childAbsolutePath, isDirectory: isDirectory) }) {
                continue
            }

            let size = allocatedSize(from: resourceValues)
            let modified = resourceValues?.contentModificationDate
            
            if isDirectory && !isSymbolicLink {
                let child = try await scanDirectory(
                    at: itemURL,
                    relativePath: childRelativePath,
                    exclusions: exclusions
                )
                totalSize += child.size
                children.append(child)
            } else {
                totalSize += size
                filesScanned += 1
                totalSizeScanned += size
                reportProgress(currentPath: itemURL.path)
                children.append(FileItem(
                    name: name,
                    path: itemURL,
                    size: size,
                    isDirectory: false,
                    modified: modified,
                    isTrashable: isTrashable(itemURL)
                ))
            }
        }

        children.sort(by: sortBySizeThenName)
        reportProgress(currentPath: url.path, force: true)
        
        return FileItem(
            name: displayName(for: url),
            path: url,
            size: totalSize,
            isDirectory: true,
            children: children,
            modified: directoryValues?.contentModificationDate,
            isTrashable: isTrashable(url)
        )
    }

    private func allocatedSize(from values: URLResourceValues?) -> Int64 {
        if let fileAllocatedSize = values?.fileAllocatedSize {
            return Int64(fileAllocatedSize)
        }
        if let totalFileAllocatedSize = values?.totalFileAllocatedSize {
            return Int64(totalFileAllocatedSize)
        }
        return Int64(values?.fileSize ?? 0)
    }

    private func reportProgress(currentPath: String, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastProgressUpdate) >= 0.1 else {
            return
        }

        lastProgressUpdate = now
        progressHandler?(ScanProgress(
            filesScanned: filesScanned,
            currentPath: currentPath,
            totalSize: totalSizeScanned
        ))
    }

    private func sortBySizeThenName(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        if lhs.size == rhs.size {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return lhs.size > rhs.size
    }

    private func displayName(for url: URL) -> String {
        if !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }
        return url.path
    }

    private func isTrashable(_ url: URL) -> Bool {
        let protectedPaths: Set<String> = [
            "/",
            "/System",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/private",
            "/dev",
            "/Volumes"
        ]

        if protectedPaths.contains(url.path) {
            return false
        }

        return fileManager.isDeletableFile(atPath: url.path)
    }
    
    enum ScanError: Error {
        case cancelled
    }
}
