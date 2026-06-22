import SwiftUI

struct ScanWorkspaceView: View {
    @ObservedObject var viewModel: ScanViewModel
    @Binding var showingFolderPicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScanToolbarView(viewModel: viewModel, showingFolderPicker: $showingFolderPicker)

            Divider()

            if viewModel.hasScanned {
                ZStack {
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

                    if viewModel.isPreparingCategoryView,
                       let selectedCategory = viewModel.selectedCategory,
                       selectedCategory != .all {
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(0.72)
                            .ignoresSafeArea()

                        ProgressView("Preparing \(selectedCategory.rawValue.lowercased()) view...")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(radius: 8)
                    }
                }
            } else {
                ScanEmptyStateView()
            }
        }
    }
}
