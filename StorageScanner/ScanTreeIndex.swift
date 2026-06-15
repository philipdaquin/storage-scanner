import Foundation

struct ScanTreeIndex {
    struct Node {
        let item: FileItem
        let parentID: UUID?
        let childIDs: [UUID]
    }

    private(set) var nodesByID: [UUID: Node] = [:]
    private(set) var rootID: UUID?

    init(root: FileItem?) {
        guard let root else { return }
        rootID = root.id
        buildIndex(for: root, parentID: nil)
    }

    func node(for id: UUID) -> Node? {
        nodesByID[id]
    }

    func item(for id: UUID) -> FileItem? {
        nodesByID[id]?.item
    }

    func breadcrumbPath(for currentPath: [UUID]) -> [FileItem] {
        guard let rootID else { return [] }

        if currentPath.isEmpty {
            guard let root = item(for: rootID) else { return [] }
            return [root]
        }

        guard let currentID = currentPath.last,
              let currentNode = nodesByID[currentID] else {
            guard let root = item(for: rootID) else { return [] }
            return [root]
        }

        var path: [FileItem] = [currentNode.item]
        var parentID = currentNode.parentID

        while let id = parentID, let node = nodesByID[id] {
            path.append(node.item)
            parentID = node.parentID
        }

        if let root = item(for: rootID), path.last?.id != root.id {
            path.append(root)
        }

        return path.reversed()
    }

    func descendants(of id: UUID) -> [FileItem] {
        guard let node = nodesByID[id] else { return [] }

        var result: [FileItem] = [node.item]
        for childID in node.childIDs {
            result.append(contentsOf: descendants(of: childID))
        }
        return result
    }

    func descendantIDs(of id: UUID) -> [UUID] {
        guard let node = nodesByID[id] else { return [] }

        var result: [UUID] = [node.item.id]
        for childID in node.childIDs {
            result.append(contentsOf: descendantIDs(of: childID))
        }
        return result
    }

    private mutating func buildIndex(for item: FileItem, parentID: UUID?) {
        let childIDs = item.children?.map(\.id) ?? []
        nodesByID[item.id] = Node(item: item, parentID: parentID, childIDs: childIDs)
        for child in item.children ?? [] {
            buildIndex(for: child, parentID: item.id)
        }
    }
}
