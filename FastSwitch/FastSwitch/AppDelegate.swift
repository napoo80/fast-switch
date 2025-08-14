import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Carbon hotkey callback
private func hotKeyHandler(_ nextHandler: EventHandlerCallRef?,
                           _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hkID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hkID)
    guard status == noErr else { return status }
    let keyCode = hkID.id
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.handleHotKey(keyCode: keyCode)
    return noErr
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []

    // Double-tap detection
    private var lastKeyCode: UInt32?
    private var lastPressDate: Date?
    private let doubleTapWindow: TimeInterval = 0.45
    private let actionDelay: TimeInterval = 0.12

    // F-keys → apps/acciones
    private let mapping: [UInt32: String] = [
        UInt32(kVK_F1):  "com.google.Chrome",
        UInt32(kVK_F2):  "com.microsoft.VSCode",            // 1 tap: VSCode, 2 taps: ⌘Esc (Claude Code)
        UInt32(kVK_F3):  "com.todesktop.230313mzl4w4u92",
        UInt32(kVK_F4):  "com.apple.finder",

        UInt32(kVK_F5):  "action:meet-mic",                 // ⌘D (Meet)
        UInt32(kVK_F6):  "action:meet-cam",                 // ⌘E (Meet)
        //UInt32(kVK_F7):  "action:insta360-track",           // ⌥T (AI tracking)
        UInt32(kVK_F8):  "com.spotify.client",
        UInt32(kVK_F9):  "com.tinyspeck.slackmacgap",
        UInt32(kVK_F10): "notion.id",
        UInt32(kVK_F11): "com.apple.TextEdit",
        UInt32(kVK_F12): "com.apple.Terminal"
    ]

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only (hide Dock & app switcher)
        NSApp.setActivationPolicy(.accessory)

        // Ask for Accessibility if needed
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        // Status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "F→"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Solicitar permisos…", action: #selector(requestAutomationPrompts), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // Hotkeys
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyHandler,
                            1,
                            &eventType,
                            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                            &eventHandlerRef)
        registerHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) { unregisterHotkeys() }

    private func registerHotkeys() {
        unregisterHotkeys()
        for (keyCode, _) in mapping {
            var ref: EventHotKeyRef?
            var id = EventHotKeyID(signature: OSType(0x484B5953), id: keyCode) // 'HKYS'
            RegisterEventHotKey(keyCode, 0, id, GetApplicationEventTarget(), 0, &ref)
            hotKeys.append(ref)
        }
    }
    private func unregisterHotkeys() {
        for hk in hotKeys { if let hk { UnregisterEventHotKey(hk) } }
        hotKeys.removeAll()
    }

    // MARK: - Main handler
    fileprivate func handleHotKey(keyCode: UInt32) {
        guard let target = mapping[keyCode] else { return }
        let now = Date()
        let isDoubleTap = (lastKeyCode == keyCode) && (lastPressDate != nil)
                       && (now.timeIntervalSince(lastPressDate!) < doubleTapWindow)
        lastKeyCode = keyCode
        lastPressDate = now

        if target.hasPrefix("action:") {
            switch target {
            case "action:meet-mic": toggleMeetMic()
            case "action:meet-cam": toggleMeetCam()
            case "action:insta360-track": toggleInsta360Tracking()
            default: break
            }
            return
        }

        if isDoubleTap {
            activateApp(bundleID: target) { [weak self] in self?.triggerInAppAction(for: target) }
        } else {
            activateApp(bundleID: target, completion: nil)
        }
    }

    // MARK: - Activation / double-tap actions
    private func activateApp(bundleID: String, completion: (() -> Void)?) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        var config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            if let completion { DispatchQueue.main.asyncAfter(deadline: .now() + self.actionDelay) { completion() } }
        }
    }

    private func triggerInAppAction(for bundleID: String) {
        switch bundleID {
        case "com.microsoft.VSCode":
            // F2 double → ⌘Esc (Claude Code)
            sendKeyCode(53, command: true)                         // 53 = Escape
        case "com.google.Chrome", "com.apple.finder", "com.apple.Terminal":
            sendShortcut(letter: "t", command: true)               // ⌘T
        case "com.spotify.client":
            playPauseSpotifyWithRetry()                            // simple toggle
        case "com.apple.TextEdit":
            sendShortcut(letter: "n", command: true)               // ⌘N
        case "notion.id", "com.notion.Notion":
            sendShortcut(letter: "n", command: true)               // ⌘N
        default:
            break
        }
    }

    // MARK: - Permissions (Chrome / System Events / Spotify) — SAFE
    @objc private func requestAutomationPrompts() {
        preopenIfNeeded(bundleID: "com.google.Chrome")
        preopenIfNeeded(bundleID: "com.spotify.client")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }

            // System Events: harmless query (no keystroke)
            self.runAppleScript(#"""
            tell application id "com.apple.systemevents"
                count processes
            end tell
            """#)

            // Chrome: harmless query
            self.runAppleScript(#"""
            tell application id "com.google.Chrome"
                if (count of windows) is 0 then return "no windows"
                get title of front window
            end tell
            """#)

            // Spotify (by bundle id) → triggers its Automation row
            self.runAppleScript(#"""tell application id "com.spotify.client" to player state"""#)
        }
    }

    private func preopenIfNeeded(bundleID: String) {
        guard !isAppRunning(bundleID: bundleID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        var cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in }
    }

    // MARK: - Meet (Chrome)
    private func toggleMeetMic() {
        let chrome = "com.google.Chrome"
        activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { self.sendShortcut(letter: "d", command: true) } // ⌘D
        }
    }
    private func toggleMeetCam() {
        let chrome = "com.google.Chrome"
        activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { self.sendShortcut(letter: "e", command: true) } // ⌘E
        }
    }
    private func chromeFrontTabIsMeet() -> Bool {
        let script = #"""
        tell application id "com.google.Chrome"
            if (count of windows) is 0 then return false
            set theURL to URL of active tab of front window
            return theURL contains "meet.google.com"
        end tell
        """#
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { print("AppleScript Chrome URL error:", error) }
        return (result?.booleanValue) ?? false
    }

    // MARK: - Insta360 Link Controller (F7 → ⌥T)
    private func toggleInsta360Tracking() {
        openInsta360IfNeeded { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.sendShortcut(letter: "t", option: true) // ⌥T
            }
        }
    }
    private func openInsta360IfNeeded(completion: (() -> Void)? = nil) {
        let candidates = [
            "com.insta360.linkcontroller",
            "com.insta360.LinkController",
            "com.arashivision.Insta360LinkController",
            "com.arashivision.insta360LinkController"
        ]
        let running = NSWorkspace.shared.runningApplications
        if running.contains(where: { app in
            (app.bundleIdentifier != nil && candidates.contains(app.bundleIdentifier!)) ||
            (app.localizedName ?? "").localizedCaseInsensitiveContains("Insta360 Link Controller")
        }) { completion?(); return }

        for bid in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                var cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in completion?() }
                return
            }
        }
        // Fallback by name in Applications folders
        let fm = FileManager.default
        for dir in ["/Applications", "\(NSHomeDirectory())/Applications"] {
            if let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                       includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles]),
               let appURL = items.first(where: {
                   $0.pathExtension == "app" &&
                   $0.lastPathComponent.lowercased().contains("insta360") &&
                   $0.lastPathComponent.lowercased().contains("link")
               }) {
                var cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, _ in completion?() }
                return
            }
        }
        completion?()
    }

    // MARK: - Spotify (bundle id)
    private func playPauseSpotifyWithRetry() {
        func tryPlay(_ remaining: Int) {
            if isAppRunning(bundleID: "com.spotify.client") {
                runAppleScript(#"tell application "Spotify" to playpause"#)
            } else if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tryPlay(remaining - 1) }
            } else {
                print("Spotify no inició a tiempo; omitido play/pause.")
            }
        }
        if !isAppRunning(bundleID: "com.spotify.client") {
            activateApp(bundleID: "com.spotify.client", completion: nil)
        }
        tryPlay(10)
    }

    // MARK: - Utilities
    private func isAppRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    // System Events keystrokes
    private func sendShortcut(letter: String,
                              command: Bool = false,
                              shift: Bool = false,
                              option: Bool = false,
                              control: Bool = false) {
        var mods: [String] = []
        if command { mods.append("command down") }
        if shift   { mods.append("shift down") }
        if option  { mods.append("option down") }
        if control { mods.append("control down") }
        let usingPart = mods.isEmpty ? "" : " using {\(mods.joined(separator: ", "))}"
        let script = #"""
        tell application id "com.apple.systemevents"
            keystroke "\#(letter)"\#(usingPart)
        end tell
        """#
        runAppleScript(script)
    }

    private func sendKeyCode(_ code: Int,
                             command: Bool = false,
                             shift: Bool = false,
                             option: Bool = false,
                             control: Bool = false) {
        var mods: [String] = []
        if command { mods.append("command down") }
        if shift   { mods.append("shift down") }
        if option  { mods.append("option down") }
        if control { mods.append("control down") }
        let usingPart = mods.isEmpty ? "" : " using {\(mods.joined(separator: ", "))}"
        let script = #"""
        tell application id "com.apple.systemevents"
            key code \#(code)\#(usingPart)
        end tell
        """#
        runAppleScript(script)
    }

    private func runAppleScript(_ script: String) {
        var error: NSDictionary?
        if let s = NSAppleScript(source: script) {
            _ = s.executeAndReturnError(&error)
            if let error,
               let num = error[NSAppleScript.errorNumber] as? Int {
                if num == 1002, // Accessibility not allowed
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                } else if num == -1743, // Automation not permitted
                          let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
                print("AppleScript error:", error)
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

