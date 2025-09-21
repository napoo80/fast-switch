import SwiftUI


@main
struct FastSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { PreferencesView() } // Simple preferences window
    }
}

