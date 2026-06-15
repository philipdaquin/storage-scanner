import Foundation

enum ScanCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case apps = "Applications"
    case documents = "Documents"
    case downloads = "Downloads"
    case media = "Media"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .apps: return "app.badge"
        case .documents: return "doc.text"
        case .downloads: return "arrow.down.circle"
        case .media: return "play.circle"
        }
    }

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
