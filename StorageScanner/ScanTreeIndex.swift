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
        var stack: [(item: FileItem, parentID: UUID?)] = [(root, nil)]

        while let entry = stack.popLast() {
            let childIDs = entry.item.children?.map(\.id) ?? []
            nodesByID[entry.item.id] = Node(
                item: entry.item,
                parentID: entry.parentID,
                childIDs: childIDs
            )

            for child in (entry.item.children ?? []).reversed() {
                stack.append((child, entry.item.id))
            }
        }
    }

    func node(for id: UUID) -> Node? {
        nodesByID[id]
    }

    func item(for id: UUID) -> FileItem? {
        nodesByID[id]?.item
    }

    func topLevelSelectedItems(in selectedIDs: Set<UUID>) -> [FileItem] {
        var items: [FileItem] = []

        for id in selectedIDs {
            guard let node = nodesByID[id] else { continue }

            var hasSelectedAncestor = false
            var parentID = node.parentID

            while let id = parentID {
                if selectedIDs.contains(id) {
                    hasSelectedAncestor = true
                    break
                }
                parentID = nodesByID[id]?.parentID
            }

            if !hasSelectedAncestor {
                items.append(node.item)
            }
        }

        items.sort {
            if $0.size == $1.size {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }
        return items
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

    func matchingDescendants(of id: UUID, where includesItem: (FileItem) -> Bool) -> [FileItem] {
        guard let node = nodesByID[id] else { return [] }

        var matches: [FileItem] = []
        var stack: [UUID] = [node.item.id]

        while let currentID = stack.popLast() {
            guard let currentNode = nodesByID[currentID] else { continue }

            if currentNode.item.id != rootID, includesItem(currentNode.item) {
                matches.append(currentNode.item)
            }

            for childID in currentNode.childIDs.reversed() {
                stack.append(childID)
            }
        }

        matches.sort {
            if $0.size == $1.size {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }
        return matches
    }
}
