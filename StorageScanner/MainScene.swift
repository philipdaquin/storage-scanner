import SwiftUI

struct MainScene: Scene {
    
    var body: some Scene {
        WindowGroup {
            ScanView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            AboutCommand()
            SidebarCommands()
            
            // Remove the "New Window" option from the File menu.
            CommandGroup(replacing: .newItem, addition: { })
        }
    }
}
