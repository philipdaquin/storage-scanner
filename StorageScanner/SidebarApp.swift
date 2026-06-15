import SwiftUI

@main
struct StorageScanner: App {
    
    /// Legacy app delegate.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sparkleUpdater = SparkleUpdateController()
    
    var body: some Scene {
        MainScene(updater: sparkleUpdater)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var menuBarButton: MenuBarButton?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarButton = MenuBarButton()
    }
        
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
