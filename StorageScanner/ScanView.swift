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
        .scanPresentation(viewModel: viewModel, showingFolderPicker: $showingFolderPicker)
    }
}
