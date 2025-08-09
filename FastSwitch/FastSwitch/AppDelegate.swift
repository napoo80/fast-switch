import Cocoa
import Carbon.HIToolbox // kVK_F1... and hotkey APIs

// MARK: - Global Hotkey Callback
private func hotKeyHandler(nextHandler: EventHandlerCallRef?,
                           event: EventRef?,
                           userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return noErr }

    var hkID = EventHotKeyID()
    GetEventParameter(event,
                      EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID),
                      nil,
                      MemoryLayout<EventHotKeyID>.size,
                      nil,
                      &hkID)

    let keyCode = hkID.id
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.handleHotKey(keyCode: keyCode)

    return noErr
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []

    // Map F-keys → app bundle IDs (edit to taste)
    // Tip to find bundle IDs: `osascript -e 'id of app "Google Chrome"'`
    private let mapping: [UInt32: String] = [
        UInt32(kVK_F1): "com.google.Chrome",     // F1 → Chrome
        UInt32(kVK_F2): "com.apple.Terminal",    // F2 → Terminal
        UInt32(kVK_F3): "com.microsoft.VSCode"   // F3 → VS Code
        // Add more: UInt32(kVK_F4): "com.apple.Safari", etc.
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar item (keeps app alive)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "F→"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Reload Hotkeys", action: #selector(reloadHotkeys), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // Install keyboard event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyHandler,
                            1,
                            &eventType,
                            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                            &eventHandlerRef)

        // Register global hotkeys
        registerHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotkeys()
    }

    // MARK: - Hotkey Registration
    private func registerHotkeys() {
        unregisterHotkeys()
        for (keyCode, _) in mapping {
            var ref: EventHotKeyRef?
            var id = EventHotKeyID(signature: OSType(0x484B5953), id: keyCode) // 'HKYS'
            // Second parameter = modifiers (0 = bare F1/F2/F3). Use controlKey/optionKey/cmdKey/shiftKey if desired.
            let status = RegisterEventHotKey(keyCode, 0, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr { hotKeys.append(ref) }
        }
    }

    private func unregisterHotkeys() {
        for hk in hotKeys { if let hk { UnregisterEventHotKey(hk) } }
        hotKeys.removeAll()
    }

    @objc private func reloadHotkeys() { registerHotkeys() }

    // MARK: - Handling
    fileprivate func handleHotKey(keyCode: UInt32) {
        guard let bundleID = mapping[keyCode],
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSSound.beep()
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true // bring to front if already running
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error { NSLog("Error launching \(bundleID): \(error.localizedDescription)") }
        }
    }

    // MARK: - Menu
    @objc private func quit() { NSApp.terminate(nil) }
}

