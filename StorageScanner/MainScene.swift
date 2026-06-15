import SwiftUI

struct MainScene: Scene {
    let updater: SparkleUpdateController
    
    var body: some Scene {
        WindowGroup {
            ScanView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            AboutCommand()
            SidebarCommands()
            UpdateCommands(updater: updater)
            
            // Remove the "New Window" option from the File menu.
            CommandGroup(replacing: .newItem, addition: { })
        }
    }
}
