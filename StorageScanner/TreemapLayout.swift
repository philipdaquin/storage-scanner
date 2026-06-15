import CoreGraphics
import Foundation

struct TreemapTileModel: Identifiable {
    let id: UUID
    let item: FileItem
    let frame: CGRect
}

enum TreemapLayout {
    static func rectangles(for items: [FileItem], in bounds: CGRect) -> [TreemapTileModel] {
        let sorted = items
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }

        return layout(items: sorted, in: bounds.insetBy(dx: 2, dy: 2))
    }

    private static func layout(items: [FileItem], in rect: CGRect) -> [TreemapTileModel] {
        guard let first = items.first else { return [] }
        guard items.count > 1 else {
            return [TreemapTileModel(id: first.id, item: first, frame: rect)]
        }

        let total = max(1, items.reduce(Int64(0)) { $0 + max(0, $1.size) })
        var groupSize: Int64 = 0
        var splitIndex = 0

        while splitIndex < items.count - 1 && groupSize < total / 2 {
            groupSize += max(0, items[splitIndex].size)
            splitIndex += 1
        }

        let firstItems = Array(items.prefix(splitIndex))
        let secondItems = Array(items.dropFirst(splitIndex))
        let ratio = CGFloat(groupSize) / CGFloat(total)
        let firstRect: CGRect
        let secondRect: CGRect

        if rect.width >= rect.height {
            let width = rect.width * ratio
            firstRect = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            secondRect = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = rect.height * ratio
            firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            secondRect = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }

        return layout(items: firstItems, in: firstRect) + layout(items: secondItems, in: secondRect)
    }
}
