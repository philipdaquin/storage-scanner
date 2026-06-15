import SwiftUI

/// Main scan view with checklist
struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @State private var showingFolderPicker = false
    
    var body: some View {
        NavigationView {
            CategorySidebar(selectedCategory: $viewModel.selectedCategory)
                .frame(minWidth: 180)

            ScanWorkspaceView(viewModel: viewModel, showingFolderPicker: $showingFolderPicker)
        }
        .frame(minWidth: 800, minHeight: 500)
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
        .alert("Move to Trash?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            Text("Are you sure you want to move \(viewModel.selectedCount) item(s) (\(viewModel.selectedSizeFormatted)) to Trash?")
        }
        .alert("Done", isPresented: $viewModel.hasSuccess) {
            Button("OK") { viewModel.hasSuccess = false }
        } message: {
            Text(viewModel.successMessage)
        }
    }
}
