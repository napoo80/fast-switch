import Cocoa
import Carbon.HIToolbox
import ApplicationServices
import UserNotifications

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

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []

    // Double-tap detection
    private var lastKeyCode: UInt32?
    private var lastPressDate: Date?
    private let doubleTapWindow: TimeInterval = 0.45
    private let actionDelay: TimeInterval = 0.12
    
    // Usage tracking
    private var usageTimer: Timer?
    private var sessionStartTime: Date?
    private var totalActiveTime: TimeInterval = 0
    private var lastActivityTime: Date = Date()
    private var isInCall: Bool = false
    private var manualCallToggle: Bool = false
    private var isDeepFocusEnabled: Bool = false
    private var deepFocusStartTime: Date?
    private var deepFocusTimer: Timer?
    private var deepFocusNotificationTimer: Timer?
    private var deepFocusNotificationStartTime: Date?
    private var sentNotificationIntervals: Set<TimeInterval> = []
    
    // Break sticky notifications
    private var stickyBreakStartTime: Date?
    private var stickyBreakTimer: Timer?
    private let stickyRepeatInterval: TimeInterval = 15      // reintentar cada 15s
    private let stickyMaxDuration: TimeInterval = 60 * 60    // tope 60 min
    private let stickyBreakNotificationID = "break-sticky"   // ID fijo para poder reemplazar/limpiar
    private var stickyRemindersEnabled: Bool = false  // Disabled since native Alerts work better
    
    // Deep Focus: guardá el último ID para poder limpiarlo (bugfix)
    private var lastDeepFocusNotificationID: String?
    
    // Configuration
    private let idleThreshold: TimeInterval = 300 // 5 minutes
    private let callIdleThreshold: TimeInterval = 1800 // 30 minutes
    private let checkInterval: TimeInterval = 5 // 5 seconds para testing
    private var notificationIntervals: [TimeInterval] = [60, 300, 600] // 1min, 5min, 10min para testing
    private var notificationsEnabled: Bool = true
    
    // Track current notification mode
    private enum NotificationMode {
        case testing, interval45, interval60, interval90, disabled
    }
    private var currentNotificationMode: NotificationMode = .testing

    // F-keys → apps/acciones
    private let mapping: [UInt32: String] = [
        UInt32(kVK_F1):  "com.google.Chrome",
        UInt32(kVK_F2):  "com.microsoft.VSCode",            // 1 tap: VSCode, 2 taps: ⌘Esc (Claude Code)
        UInt32(kVK_F3):  "com.todesktop.230313mzl4w4u92",
        UInt32(kVK_F4):  "com.apple.finder",

        UInt32(kVK_F5):  "action:meet-mic",                 // ⌘D (Meet)
        UInt32(kVK_F6):  "action:meet-cam",                 // ⌘E (Meet)
        UInt32(kVK_F7):  "action:deep-focus",               // enables/disables focus
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
        
        // Request notification permissions and set delegate
        requestNotificationPermissions()
        UNUserNotificationCenter.current().delegate = self

        // Status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "F→"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Solicitar permisos…", action: #selector(requestAutomationPrompts), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Usage tracking menu items
        let sessionItem = NSMenuItem(title: "Sesión: 0m", action: nil, keyEquivalent: "")
        sessionItem.tag = 100 // For easy reference
        menu.addItem(sessionItem)
        
        let callToggleItem = NSMenuItem(title: "🔘 Marcar como llamada", action: #selector(toggleCallStatus), keyEquivalent: "")
        callToggleItem.tag = 101
        menu.addItem(callToggleItem)
        
        let deepFocusItem = NSMenuItem(title: "🧘 Deep Focus: OFF", action: #selector(toggleDeepFocusFromMenu), keyEquivalent: "")
        deepFocusItem.tag = 102
        menu.addItem(deepFocusItem)
        
        menu.addItem(NSMenuItem(title: "🔄 Reiniciar sesión", action: #selector(resetSession), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Configuration submenu
        let configMenu = NSMenu()
        let configItem = NSMenuItem(title: "⚙️ Configuración", action: nil, keyEquivalent: "")
        configItem.submenu = configMenu
        
        let testingItem = NSMenuItem(title: "🔔 Testing: 1-5-10min", action: #selector(setNotificationIntervalTest), keyEquivalent: "")
        testingItem.tag = 200
        configMenu.addItem(testingItem)
        
        let interval45Item = NSMenuItem(title: "🔔 Recordatorios cada 45m", action: #selector(setNotificationInterval45), keyEquivalent: "")
        interval45Item.tag = 201
        configMenu.addItem(interval45Item)
        
        let interval60Item = NSMenuItem(title: "🔔 Recordatorios cada 60m", action: #selector(setNotificationInterval60), keyEquivalent: "")
        interval60Item.tag = 202
        configMenu.addItem(interval60Item)
        
        let interval90Item = NSMenuItem(title: "🔔 Recordatorios cada 90m", action: #selector(setNotificationInterval90), keyEquivalent: "")
        interval90Item.tag = 203
        configMenu.addItem(interval90Item)
        
        configMenu.addItem(NSMenuItem.separator())
        
        let disableItem = NSMenuItem(title: "🔕 Desactivar recordatorios", action: #selector(disableNotifications), keyEquivalent: "")
        disableItem.tag = 204
        configMenu.addItem(disableItem)
        
        configMenu.addItem(NSMenuItem.separator())
        configMenu.addItem(NSMenuItem(title: "⚙️ Ajustes de Notificaciones…", action: #selector(openNotificationsPrefs), keyEquivalent: ""))
        
        // Optional: uncomment to enable software sticky mode as fallback
        // let stickyToggleItem = NSMenuItem(title: "🔄 Modo Sticky Software", action: #selector(toggleStickyMode), keyEquivalent: "")
        // configMenu.addItem(stickyToggleItem)
        
        menu.addItem(configItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        
        print("📋 FastSwitch: Menú creado con \(menu.items.count) items")
        
        // Start usage tracking
        startUsageTracking()
        
        // Auto-enable testing mode for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setNotificationIntervalTest()
        }
        
        // Update initial menu state
        updateConfigurationMenuState()

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

    func applicationWillTerminate(_ notification: Notification) { 
        unregisterHotkeys()
        stopUsageTracking()
        deepFocusTimer?.invalidate()
        deepFocusNotificationTimer?.invalidate()
        stickyBreakTimer?.invalidate()
    }

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
            case "action:deep-focus": toggleDeepFocus()
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
        print("🎤 FastSwitch: F5 presionado - Toggle mic Meet")
        
        // Automatically set call status when using Meet controls
        if chromeFrontTabIsMeet() {
            manualCallToggle = true
            print("🎤 FastSwitch: Meet detectado, activando estado de llamada")
        }
        
        activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { 
                self.sendShortcut(letter: "d", command: true) // ⌘D
                self.manualCallToggle = true // Ensure call status is set
                print("🎤 FastSwitch: Enviado ⌘D para toggle mic")
            }
        }
    }
    private func toggleMeetCam() {
        let chrome = "com.google.Chrome"
        print("📹 FastSwitch: F6 presionado - Toggle cam Meet")
        
        // Automatically set call status when using Meet controls
        if chromeFrontTabIsMeet() {
            manualCallToggle = true
            print("📹 FastSwitch: Meet detectado, activando estado de llamada")
        }
        
        activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { 
                self.sendShortcut(letter: "e", command: true) // ⌘E
                self.manualCallToggle = true // Ensure call status is set
                print("📹 FastSwitch: Enviado ⌘E para toggle cam")
            }
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

    // MARK: - Deep Focus (F7)
    private func toggleDeepFocus() {
        isDeepFocusEnabled.toggle()
        print("🧘 FastSwitch: F7 presionado - Toggle Deep Focus: \(isDeepFocusEnabled ? "ON" : "OFF")")
        
        if isDeepFocusEnabled {
            enableDeepFocus()
        } else {
            disableDeepFocus()
        }
        
        // Update menu bar and menu items to show focus status
        updateStatusBarForFocus()
        updateMenuItems(sessionDuration: getCurrentSessionDuration())
    }
    
    private func enableDeepFocus() {
        print("🧘 FastSwitch: Activando Deep Focus...")
        
        // Enable Do Not Disturb on macOS
        let enableDNDScript = #"""
        tell application "System Events"
            tell process "Control Center"
                try
                    click menu bar item "Control Center" of menu bar 1
                    delay 0.5
                    click button "Do Not Disturb" of group 1 of window "Control Center"
                end try
            end tell
        end tell
        """#
        
        runAppleScript(enableDNDScript)
        
        // Enable Do Not Disturb in Slack
        enableSlackDND()
        
        // Start 60-minute timer
        deepFocusStartTime = Date()
        deepFocusTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
            self?.showDeepFocusCompletionNotification()
        }
        
        print("✅ FastSwitch: Deep Focus activado - DND macOS + Slack, timer 60min iniciado")
    }
    
    private func disableDeepFocus() {
        print("🧘 FastSwitch: Desactivando Deep Focus...")
        
        // Cancel timer if running
        deepFocusTimer?.invalidate()
        deepFocusTimer = nil
        
        // Disable Do Not Disturb on macOS
        let disableDNDScript = #"""
        tell application "System Events"
            tell process "Control Center"
                try
                    click menu bar item "Control Center" of menu bar 1
                    delay 0.5
                    click button "Do Not Disturb" of group 1 of window "Control Center"
                end try
            end tell
        end tell
        """#
        
        runAppleScript(disableDNDScript)
        
        // Disable Do Not Disturb in Slack
        disableSlackDND()
        
        // Calculate session duration
        let sessionDuration = deepFocusStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let minutes = Int(sessionDuration / 60)
        
        print("✅ FastSwitch: Deep Focus desactivado - DND off macOS + Slack (duración: \(minutes)min)")
        deepFocusStartTime = nil
    }
    
    private func updateStatusBarForFocus() {
        DispatchQueue.main.async {
            let focusIndicator = self.isDeepFocusEnabled ? "🧘" : ""
            let currentTitle = self.statusItem.button?.title ?? "F→"
            
            // Remove existing focus indicator if present
            let cleanTitle = currentTitle.replacingOccurrences(of: "🧘", with: "").trimmingCharacters(in: .whitespaces)
            
            // Add focus indicator if enabled
            self.statusItem.button?.title = self.isDeepFocusEnabled ? "\(focusIndicator) \(cleanTitle)" : cleanTitle
        }
    }
    
    private func enableSlackDND() {
        print("🧘 FastSwitch: Activando DND en Slack...")
        
        // Set Slack status to DND for 60 minutes
        let slackDNDScript = #"""
        tell application "Slack"
            try
                activate
                delay 0.5
                -- Try to use keyboard shortcut for DND (Cmd+Shift+D)
                tell application "System Events"
                    keystroke "d" using {command down, shift down}
                end tell
            on error
                -- Fallback: could implement manual UI interaction if needed
                log "Could not set Slack DND via shortcut"
            end try
        end tell
        """#
        
        runAppleScript(slackDNDScript)
        print("✅ FastSwitch: Comando DND enviado a Slack")
    }
    
    private func disableSlackDND() {
        print("🧘 FastSwitch: Desactivando DND en Slack...")
        
        // Clear Slack DND
        let slackClearDNDScript = #"""
        tell application "Slack"
            try
                activate
                delay 0.5
                -- Try to use keyboard shortcut to clear DND (Cmd+Shift+D again)
                tell application "System Events"
                    keystroke "d" using {command down, shift down}
                end tell
            on error
                log "Could not clear Slack DND via shortcut"
            end try
        end tell
        """#
        
        runAppleScript(slackClearDNDScript)
        print("✅ FastSwitch: DND de Slack desactivado")
    }
    
    private func showDeepFocusCompletionNotification() {
        print("🧘 FastSwitch: Sesión Deep Focus de 60min completada")
        
        // Start sticky notification tracking
        deepFocusNotificationStartTime = Date()
        startStickyDeepFocusNotification()
    }
    
    private func startStickyDeepFocusNotification() {
        // Cancel any existing notification timer
        deepFocusNotificationTimer?.invalidate()
        
        // Send the notification
        sendDeepFocusNotification()
        
        // Set up timer to re-send notification every 15 seconds for 1 minute if not dismissed
        deepFocusNotificationTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            guard let self = self,
                  let startTime = self.deepFocusNotificationStartTime else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed >= 60 { // 1 minute has passed
                print("🧘 FastSwitch: Sticky notification timer expired after 1 minute")
                timer.invalidate()
                self.deepFocusNotificationTimer = nil
                self.deepFocusNotificationStartTime = nil
            } else {
                // Re-send notification to keep it visible
                print("🧘 FastSwitch: Re-enviando notificación sticky (\(Int(elapsed))s elapsed)")
                self.sendDeepFocusNotification()
            }
        }
    }
    
    private func sendDeepFocusNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🧘 Deep Focus Session Complete"
        content.body = "⏰ You've completed 60 minutes of focused work!\n\n🎉 Great job staying focused!\n\n💡 Consider taking a break or continuing your session.\n\n👆 MUST CLICK to dismiss this sticky notification."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Crystal.aiff"))
        content.badge = 1
        content.interruptionLevel = .critical  // Use critical for maximum persistence
        content.categoryIdentifier = "DEEP_FOCUS_COMPLETE"
        
        // Add action buttons
        let continueAction = UNNotificationAction(
            identifier: "CONTINUE_FOCUS_ACTION",
            title: "🧘 Continue Focusing",
            options: []
        )
        
        let takeBreakAction = UNNotificationAction(
            identifier: "TAKE_BREAK_ACTION",
            title: "☕ Take a Break",
            options: []
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_FOCUS_ACTION",
            title: "✅ Got it!",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "DEEP_FOCUS_COMPLETE",
            actions: [continueAction, takeBreakAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        // Use timestamp to make each notification unique
        let id = "deep-focus-complete-\(Int(Date().timeIntervalSince1970))"
        lastDeepFocusNotificationID = id
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando notificación Deep Focus: \(error)")
            } else {
                print("✅ FastSwitch: Notificación Deep Focus sticky enviada")
            }
        }
    }
    
    private func stopStickyDeepFocusNotification() {
        print("🧘 FastSwitch: Deteniendo notificaciones sticky Deep Focus")
        deepFocusNotificationTimer?.invalidate()
        deepFocusNotificationTimer = nil
        deepFocusNotificationStartTime = nil
        
        // Clear any pending notifications using the saved ID
        if let id = lastDeepFocusNotificationID {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            lastDeepFocusNotificationID = nil
        }
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
    
    // MARK: - Usage Tracking
    private func requestNotificationPermissions() {
        print("🔔 FastSwitch: Solicitando permisos de notificación...")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ FastSwitch: Error en permisos de notificación: \(error)")
                } else if granted {
                    print("✅ FastSwitch: Permisos de notificación concedidos")
                } else {
                    print("⚠️ FastSwitch: Permisos de notificación denegados")
                }
            }
        }
    }
    
    private func startUsageTracking() {
        sessionStartTime = Date()
        lastActivityTime = Date()
        sentNotificationIntervals.removeAll()
        
        print("🚀 FastSwitch: Iniciando seguimiento de uso")
        print("⏰ FastSwitch: Intervalo de verificación: \(checkInterval)s")
        print("📊 FastSwitch: Intervalos de notificación: \(notificationIntervals.map { Int($0) })s")
        
        usageTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkUserActivity()
        }
    }
    
    private func stopUsageTracking() {
        print("🛑 FastSwitch: Deteniendo seguimiento de uso")
        usageTimer?.invalidate()
        usageTimer = nil
    }
    
    private func checkUserActivity() {
        let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let keyboardIdleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        
        let minIdleTime = min(idleTime, keyboardIdleTime)
        let currentTime = Date()
        
        // Check if user is in a call
        updateCallStatus()
        
        let effectiveIdleThreshold = isInCall ? callIdleThreshold : idleThreshold
        let sessionDuration = getCurrentSessionDuration()
        
        print("🔍 FastSwitch: Idle tiempo: \(Int(minIdleTime))s (mouse: \(Int(idleTime))s, teclado: \(Int(keyboardIdleTime))s)")
        print("📞 FastSwitch: En llamada: \(isInCall) (manual: \(manualCallToggle))")
        print("⏰ FastSwitch: Sesión actual: \(Int(sessionDuration))s (\(Int(sessionDuration/60))min)")
        
        if minIdleTime < effectiveIdleThreshold {
            // User is active
            lastActivityTime = currentTime
            print("✅ FastSwitch: Usuario activo (umbral: \(Int(effectiveIdleThreshold))s)")
            
            // Calculate session time and check for notifications
            if let startTime = sessionStartTime {
                let sessionDuration = currentTime.timeIntervalSince(startTime)
                checkForBreakNotification(sessionDuration: sessionDuration)
                updateStatusBarTitle(sessionDuration: sessionDuration)
            }
        } else {
            // User is idle - could pause session tracking if desired
            print("😴 FastSwitch: Usuario inactivo (umbral: \(Int(effectiveIdleThreshold))s)")
            updateStatusBarTitle(sessionDuration: getCurrentSessionDuration())
        }
        
        print("---")
    }
    
    private func updateCallStatus() {
        // Check for video call applications
        let callApps = [
            "com.google.Chrome", // Check if Chrome has Meet tab
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.cisco.webexmeetingsapp",
            "com.skype.skype"
        ]
        
        var inCall = manualCallToggle
        var detectedApps: [String] = []
        
        for bundleID in callApps {
            if isAppRunning(bundleID: bundleID) {
                detectedApps.append(bundleID)
                if bundleID == "com.google.Chrome" {
                    // Check if Chrome has a Meet tab
                    let hasMeet = chromeFrontTabIsMeet()
                    if hasMeet {
                        inCall = true
                        print("🌐 FastSwitch: Chrome con Meet tab detectado")
                    }
                } else {
                    inCall = true
                    print("📹 FastSwitch: App de videollamada detectada: \(bundleID)")
                }
            }
        }
        
        if !detectedApps.isEmpty {
            print("📱 FastSwitch: Apps de llamada corriendo: \(detectedApps)")
        }
        
        // Note: Microphone usage detection would require additional implementation on macOS
        // Could use AVCaptureDevice.authorizationStatus(for: .audio) if needed
        
        let wasInCall = isInCall
        isInCall = inCall
        
        if wasInCall != isInCall {
            print("🔄 FastSwitch: Estado de llamada cambió: \(wasInCall) → \(isInCall)")
        }
    }
    
    private func getCurrentSessionDuration() -> TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    private func checkForBreakNotification(sessionDuration: TimeInterval) {
        guard notificationsEnabled else { 
            print("🔕 FastSwitch: Notificaciones deshabilitadas")
            return 
        }
        
        for (index, interval) in notificationIntervals.enumerated() {
            // Check if we've already sent a notification for this interval
            if sentNotificationIntervals.contains(interval) {
                continue
            }
            
            // Send notification when we reach or exceed the interval
            if sessionDuration >= interval {
                print("🔔 FastSwitch: Enviando notificación #\(index + 1) - Intervalo: \(Int(interval))s (sesión: \(Int(sessionDuration))s)")
                sendBreakNotification(sessionDuration: sessionDuration)
                sentNotificationIntervals.insert(interval)
                
                // Start sticky notifications if enabled
                if stickyRemindersEnabled {
                    startStickyBreakNotifications()
                }
                break
            } else if sessionDuration >= interval - checkInterval {
                let timeLeft = Int(interval - sessionDuration)
                print("⏰ FastSwitch: Próxima notificación en \(timeLeft)s (intervalo: \(Int(interval))s)")
            }
        }
    }
    
    private func sendBreakNotification(sessionDuration: TimeInterval, overrideIdentifier: String? = nil) {
        let content = UNMutableNotificationContent()
        
        let hours = Int(sessionDuration) / 3600
        let minutes = Int(sessionDuration) % 3600 / 60
        let seconds = Int(sessionDuration) % 60
        
        print("📬 FastSwitch: Preparando notificación - Tiempo: \(hours)h \(minutes)m \(seconds)s")
        
        if isInCall {
            content.title = "🔔 Break Reminder - Meeting Break"
            content.body = "You've been in meetings for \(hours)h \(minutes)m.\n\n💡 Consider a short break when possible.\n\n👆 Click to dismiss this reminder."
            content.sound = UNNotificationSound(named: UNNotificationSoundName("Glass.aiff"))
            print("🔇 FastSwitch: Notificación de llamada")
        } else {
            content.title = "⚠️ Time for a Break! - Work Break"
            content.body = "You've been working for \(hours)h \(minutes)m.\n\n🚶‍♂️ Take a 5-10 minute break to stay healthy.\n\n👆 Click to dismiss this reminder."
            content.sound = UNNotificationSound(named: UNNotificationSoundName("Basso.aiff"))
            print("🔊 FastSwitch: Notificación de trabajo")
        }
        
        // Make notification more attention-grabbing
        content.categoryIdentifier = "BREAK_REMINDER"
        content.badge = 1
        content.interruptionLevel = .timeSensitive
        
        // Add action buttons that require user interaction
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "✅ Got it!",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION", 
            title: "⏰ Remind me in 5 min",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "BREAK_REMINDER",
            actions: [dismissAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let id = overrideIdentifier ?? "break-\(Int(sessionDuration))"
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        
        print("📤 FastSwitch: Enviando notificación persistente...")
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando notificación: \(error)")
            } else {
                print("✅ FastSwitch: Notificación persistente enviada correctamente (id: \(id))")
            }
        }
    }
    
    private func startStickyBreakNotifications() {
        stopStickyBreakNotifications()
        stickyBreakStartTime = Date()
        
        // primer envío inmediato con ID fijo
        sendBreakNotification(sessionDuration: getCurrentSessionDuration(),
                              overrideIdentifier: stickyBreakNotificationID)
        
        stickyBreakTimer = Timer.scheduledTimer(withTimeInterval: stickyRepeatInterval,
                                                repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard let start = self.stickyBreakStartTime else { timer.invalidate(); return }
            
            if Date().timeIntervalSince(start) >= self.stickyMaxDuration {
                print("⏹️ Sticky break: alcanzado tiempo máximo")
                self.stopStickyBreakNotifications()
                return
            }
            
            print("🔁 Reenviando break sticky…")
            self.sendBreakNotification(sessionDuration: self.getCurrentSessionDuration(),
                                       overrideIdentifier: self.stickyBreakNotificationID)
        }
    }
    
    private func stopStickyBreakNotifications() {
        stickyBreakTimer?.invalidate()
        stickyBreakTimer = nil
        stickyBreakStartTime = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [stickyBreakNotificationID])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [stickyBreakNotificationID])
        print("🔕 FastSwitch: Sticky break notifications stopped")
    }
    
    private func updateStatusBarTitle(sessionDuration: TimeInterval) {
        let hours = Int(sessionDuration) / 3600
        let minutes = Int(sessionDuration) % 3600 / 60
        
        let timeString = hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
        let callIndicator = isInCall ? "📞" : ""
        
        DispatchQueue.main.async {
            self.statusItem.button?.title = "F→ \(callIndicator)\(timeString)"
            self.updateMenuItems(sessionDuration: sessionDuration)
        }
    }
    
    private func updateMenuItems(sessionDuration: TimeInterval) {
        guard let menu = statusItem.menu else { return }
        
        let hours = Int(sessionDuration) / 3600
        let minutes = Int(sessionDuration) % 3600 / 60
        let timeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        
        // Update session time display
        if let sessionItem = menu.item(withTag: 100) {
            let statusText = isInCall ? "📞 En llamada: \(timeString)" : "⏰ Sesión: \(timeString)"
            sessionItem.title = statusText
        }
        
        // Update call toggle button
        if let callToggleItem = menu.item(withTag: 101) {
            if manualCallToggle {
                callToggleItem.title = "🔴 Desmarcar llamada"
            } else {
                callToggleItem.title = "🔘 Marcar como llamada"
            }
        }
        
        // Update deep focus status
        if let deepFocusItem = menu.item(withTag: 102) {
            if isDeepFocusEnabled, let startTime = deepFocusStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = max(0, 3600 - elapsed) // 60 minutes = 3600 seconds
                let remainingMinutes = Int(remaining / 60)
                deepFocusItem.title = "🧘 Deep Focus: ON (\(remainingMinutes)min left)"
            } else {
                deepFocusItem.title = "🧘 Deep Focus: OFF"
            }
        }
    }
    
    @objc private func toggleCallStatus() {
        manualCallToggle.toggle()
        print("🔄 FastSwitch: Toggle manual de llamada: \(manualCallToggle)")
    }
    
    @objc private func toggleDeepFocusFromMenu() {
        toggleDeepFocus()
    }
    
    @objc private func openNotificationsPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Uncomment if you want to toggle software sticky mode
    /*
    @objc private func toggleStickyMode() {
        stickyRemindersEnabled.toggle()
        print("🔄 FastSwitch: Modo sticky software: \(stickyRemindersEnabled ? "ON" : "OFF")")
    }
    */
    
    @objc private func resetSession() {
        sessionStartTime = Date()
        totalActiveTime = 0
        sentNotificationIntervals.removeAll()
        print("🔄 FastSwitch: Sesión reiniciada")
    }
    
    private func updateConfigurationMenuState() {
        guard let menu = statusItem.menu else { return }
        
        // Find the configuration submenu
        var configSubmenu: NSMenu?
        for item in menu.items {
            if item.title == "⚙️ Configuración", let submenu = item.submenu {
                configSubmenu = submenu
                break
            }
        }
        
        guard let configMenu = configSubmenu else { return }
        
        // Clear all checkmarks first
        for item in configMenu.items {
            if item.tag >= 200 && item.tag <= 204 {
                item.state = .off
            }
        }
        
        // Set checkmark for current mode
        let tagToCheck: Int
        switch currentNotificationMode {
        case .testing:
            tagToCheck = 200
        case .interval45:
            tagToCheck = 201
        case .interval60:
            tagToCheck = 202
        case .interval90:
            tagToCheck = 203
        case .disabled:
            tagToCheck = 204
        }
        
        if let itemToCheck = configMenu.item(withTag: tagToCheck) {
            itemToCheck.state = .on
        }
    }
    
    // MARK: - Configuration Methods
    @objc private func setNotificationIntervalTest() {
        notificationIntervals = [60, 300, 600] // 1min, 5min, 10min para testing
        notificationsEnabled = true
        currentNotificationMode = .testing
        sentNotificationIntervals.removeAll() // Reset sent notifications when changing intervals
        updateConfigurationMenuState()
        print("🧪 FastSwitch: Configurado en modo testing - Intervalos: 1min, 5min, 10min")
    }
    
    @objc private func setNotificationInterval45() {
        notificationIntervals = [2700, 5400, 8100] // 45min, 1.5hr, 2.25hr
        notificationsEnabled = true
        currentNotificationMode = .interval45
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        print("⏰ FastSwitch: Configurado intervalos 45min")
    }
    
    @objc private func setNotificationInterval60() {
        notificationIntervals = [3600, 7200, 10800] // 1hr, 2hr, 3hr
        notificationsEnabled = true
        currentNotificationMode = .interval60
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        print("⏰ FastSwitch: Configurado intervalos 60min")
    }
    
    @objc private func setNotificationInterval90() {
        notificationIntervals = [5400, 10800, 16200] // 1.5hr, 3hr, 4.5hr
        notificationsEnabled = true
        currentNotificationMode = .interval90
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        print("⏰ FastSwitch: Configurado intervalos 90min")
    }
    
    @objc private func disableNotifications() {
        notificationsEnabled = false
        currentNotificationMode = .disabled
        updateConfigurationMenuState()
        print("🔕 FastSwitch: Notificaciones deshabilitadas")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is active
        completionHandler([.alert, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "DISMISS_ACTION":
            print("✅ FastSwitch: Usuario confirmó notificación de descanso")
            // Stop sticky break notifications
            stopStickyBreakNotifications()
            // Clear badge
            NSApp.dockTile.badgeLabel = nil
            
        case "SNOOZE_ACTION":
            print("⏰ FastSwitch: Usuario pospuso notificación por 5 minutos")
            // Stop sticky break notifications
            stopStickyBreakNotifications()
            // Schedule a snooze notification in 5 minutes
            scheduleSnoozeNotification()
            
        case "CONTINUE_FOCUS_ACTION":
            print("🧘 FastSwitch: Usuario eligió continuar Deep Focus")
            // Stop sticky notifications since user clicked
            stopStickyDeepFocusNotification()
            // Restart 60-minute timer
            deepFocusTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
                self?.showDeepFocusCompletionNotification()
            }
            NSApp.dockTile.badgeLabel = nil
            
        case "TAKE_BREAK_ACTION":
            print("☕ FastSwitch: Usuario eligió tomar descanso")
            // Stop sticky notifications since user clicked
            stopStickyDeepFocusNotification()
            // Disable Deep Focus
            if isDeepFocusEnabled {
                toggleDeepFocus()
            }
            NSApp.dockTile.badgeLabel = nil
            
        case "DISMISS_FOCUS_ACTION":
            print("✅ FastSwitch: Usuario confirmó notificación Deep Focus")
            // Stop sticky notifications since user clicked
            stopStickyDeepFocusNotification()
            NSApp.dockTile.badgeLabel = nil
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            print("👆 FastSwitch: Usuario tocó la notificación")
            // Stop sticky notifications based on notification type
            let categoryIdentifier = response.notification.request.content.categoryIdentifier
            if categoryIdentifier == "DEEP_FOCUS_COMPLETE" {
                stopStickyDeepFocusNotification()
            } else if categoryIdentifier == "BREAK_REMINDER" {
                stopStickyBreakNotifications()
            }
            NSApp.dockTile.badgeLabel = nil
            
        default:
            break
        }
        
        completionHandler()
    }
    
    private func scheduleSnoozeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Snooze Reminder"
        content.body = "🔔 This is your 5-minute break reminder.\n\n🚶‍♂️ Don't forget to take that break!\n\n👆 Click to dismiss."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Ping.aiff"))
        content.badge = 1
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "SNOOZE_REMINDER"
        
        // Create actions for snooze notification
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_SNOOZE_ACTION",
            title: "✅ Got it!",
            options: []
        )
        
        let snoozeCategory = UNNotificationCategory(
            identifier: "SNOOZE_REMINDER",
            actions: [dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([snoozeCategory])
        
        // Schedule for 5 minutes from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false) // 5 minutes
        
        let request = UNNotificationRequest(
            identifier: "snooze-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error programando snooze: \(error)")
            } else {
                print("✅ FastSwitch: Snooze programado para 5 minutos")
            }
        }
    }
}

