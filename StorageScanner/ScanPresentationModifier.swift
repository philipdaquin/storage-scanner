import SwiftUI

struct ScanPresentationModifier: ViewModifier {
    @ObservedObject var viewModel: ScanViewModel
    @Binding var showingFolderPicker: Bool

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.scan(url: url)
                }
            }
            .onChange(of: viewModel.selectedCategory) { category in
                viewModel.applyCategory(category)
            }
            .alert("Error", isPresented: $viewModel.hasError) {
                Button("OK", role: .cancel) { viewModel.hasError = false }
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $viewModel.showDeleteConfirmation) {
                DeleteReviewSheet(
                    items: viewModel.selectedDeletionItems,
                    selectedSize: viewModel.selectedSize,
                    onCancel: { viewModel.showDeleteConfirmation = false },
                    onConfirm: { viewModel.confirmDelete() }
                )
            }
            .alert("Done", isPresented: $viewModel.hasSuccess) {
                Button("OK") { viewModel.hasSuccess = false }
            } message: {
                Text(viewModel.successMessage)
            }
    }
}

extension View {
    func scanPresentation(viewModel: ScanViewModel, showingFolderPicker: Binding<Bool>) -> some View {
        modifier(ScanPresentationModifier(viewModel: viewModel, showingFolderPicker: showingFolderPicker))
    }
}
