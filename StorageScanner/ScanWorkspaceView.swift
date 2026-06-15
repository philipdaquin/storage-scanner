import SwiftUI

struct ScanWorkspaceView: View {
    @ObservedObject var viewModel: ScanViewModel
    @Binding var showingFolderPicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScanToolbarView(viewModel: viewModel, showingFolderPicker: $showingFolderPicker)

            Divider()

            if viewModel.hasScanned {
                VStack(spacing: 0) {
                    BreadcrumbBar(
                        items: viewModel.breadcrumbs,
                        onNavigate: viewModel.navigateToBreadcrumb
                    )
                    Divider()

                    if viewModel.viewMode == .list {
                        FileListView(
                            item: viewModel.displayedItem,
                            canNavigateUp: !viewModel.currentPath.isEmpty && (viewModel.selectedCategory == nil || viewModel.selectedCategory == .all),
                            onNavigate: viewModel.navigateTo,
                            onNavigateUp: viewModel.navigateUp,
                            onSelect: viewModel.toggleSelection,
                            selectedItems: viewModel.selectedItems
                        )
                    } else {
                        TreemapView(
                            items: viewModel.treemapItems,
                            selectedItems: viewModel.selectedItems,
                            onSelect: viewModel.toggleSelection
                        )
                    }

                    Divider()

                    DeleteFooter(
                        selectedCount: viewModel.selectedCount,
                        selectedSize: viewModel.selectedSize,
                        onDelete: viewModel.deleteSelected
                    )
                }
            } else {
                ScanEmptyStateView()
            }
        }
    }
}
