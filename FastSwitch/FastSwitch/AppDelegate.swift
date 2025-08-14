import Cocoa
import Carbon.HIToolbox
import ApplicationServices
import UserNotifications
import Foundation
import UniformTypeIdentifiers

// MARK: - Data Structures for Persistent Storage
struct SessionRecord: Codable {
    let start: Date
    let duration: TimeInterval
}

struct DailyUsageData: Codable {
    let date: Date
    var totalSessionTime: TimeInterval
    var appUsage: [String: TimeInterval]
    var breaksTaken: [SessionRecord]
    var continuousWorkSessions: [SessionRecord]
    var deepFocusSessions: [SessionRecord]
    var longestContinuousSession: TimeInterval
    var totalBreakTime: TimeInterval
    var callTime: TimeInterval
    
    init(date: Date) {
        self.date = date
        self.totalSessionTime = 0
        self.appUsage = [:]
        self.breaksTaken = []
        self.continuousWorkSessions = []
        self.deepFocusSessions = []
        self.longestContinuousSession = 0
        self.totalBreakTime = 0
        self.callTime = 0
    }
}

struct UsageHistory: Codable {
    var dailyData: [String: DailyUsageData]
    
    init() {
        self.dailyData = [:]
    }
}

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
    
    // App tracking and dashboard
    private var currentFrontApp: String?
    private var appUsageToday: [String: TimeInterval] = [:]
    private var lastAppCheckTime: Date = Date()
    private var dashboardTimer: Timer?
    private var hasShownDashboardToday: Bool = false
    
    // Break and continuous session tracking
    private var breaksTaken: [SessionRecord] = []
    private var continuousWorkSessions: [SessionRecord] = []
    private var currentContinuousSessionStart: Date?
    private var isCurrentlyOnBreak: Bool = false
    private var breakStartTime: Date?
    private var longestContinuousSession: TimeInterval = 0
    private var totalBreakTime: TimeInterval = 0
    
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
    
    // Persistent storage
    private var usageHistory: UsageHistory = UsageHistory()
    private let usageHistoryKey = "FastSwitchUsageHistory"
    private var currentDayCallTime: TimeInterval = 0
    private var callStartTime: Date?
    private var deepFocusSessionStartTime: Date?
    
    // Break timer system
    private var breakTimer: Timer?
    private var breakTimerStartTime: Date?
    private var isBreakTimerActive: Bool = false
    private var customFocusDuration: TimeInterval = 3600 // Default 60 minutes

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
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "🔄 Reiniciar sesión", action: #selector(resetSession), keyEquivalent: ""))
        
        // Reports submenu
        let reportsMenu = NSMenu()
        let reportsItem = NSMenuItem(title: "📊 Reportes", action: nil, keyEquivalent: "")
        reportsItem.submenu = reportsMenu
        
        reportsMenu.addItem(NSMenuItem(title: "📊 Ver Dashboard Diario", action: #selector(showDashboardManually), keyEquivalent: ""))
        reportsMenu.addItem(NSMenuItem(title: "📈 Reporte Semanal", action: #selector(showWeeklyReport), keyEquivalent: ""))
        reportsMenu.addItem(NSMenuItem(title: "📅 Reporte Anual", action: #selector(showYearlyReport), keyEquivalent: ""))
        reportsMenu.addItem(NSMenuItem.separator())
        reportsMenu.addItem(NSMenuItem(title: "💾 Exportar Datos", action: #selector(exportUsageData), keyEquivalent: ""))
        
        menu.addItem(reportsItem)
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
        
        // Initialize app tracking
        currentFrontApp = getCurrentFrontApp()
        lastAppCheckTime = Date()
        
        // Initialize session tracking
        currentContinuousSessionStart = Date()
        
        // Load usage history
        loadUsageHistory()
        
        // Initialize today's data if needed
        initializeTodayData()
        
        // Schedule daily dashboard
        scheduleDailyDashboard()
        
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
        // Save today's data before terminating
        saveTodayData()
        saveUsageHistory()
        
        unregisterHotkeys()
        stopUsageTracking()
        deepFocusTimer?.invalidate()
        deepFocusNotificationTimer?.invalidate()
        stickyBreakTimer?.invalidate()
        dashboardTimer?.invalidate()
        breakTimer?.invalidate()
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
        
        // Start timer with custom duration
        deepFocusStartTime = Date()
        deepFocusSessionStartTime = Date()
        deepFocusTimer = Timer.scheduledTimer(withTimeInterval: customFocusDuration, repeats: false) { [weak self] _ in
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
        
        // Calculate session duration and save it
        if let startTime = deepFocusSessionStartTime {
            let sessionDuration = Date().timeIntervalSince(startTime)
            let minutes = Int(sessionDuration / 60)
            
            // Save deep focus session to today's data
            let todayKey = getTodayKey()
            if var todayData = usageHistory.dailyData[todayKey] {
                todayData.deepFocusSessions.append(SessionRecord(start: startTime, duration: sessionDuration))
                usageHistory.dailyData[todayKey] = todayData
                saveUsageHistory()
            }
            
            print("✅ FastSwitch: Deep Focus desactivado - DND off macOS + Slack (duración: \(minutes)min)")
            deepFocusSessionStartTime = nil
        }
        
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
        let focusAnotherHourAction = UNNotificationAction(
            identifier: "FOCUS_ANOTHER_HOUR_ACTION",
            title: "🧘 Focus Another Hour",
            options: []
        )
        
        let take15BreakAction = UNNotificationAction(
            identifier: "TAKE_15MIN_BREAK_ACTION",
            title: "☕ Take 15min Break",
            options: []
        )
        
        let showSessionStatsAction = UNNotificationAction(
            identifier: "SHOW_SESSION_STATS_ACTION",
            title: "📊 Show Session Stats",
            options: [.foreground]
        )
        
        let setCustomFocusAction = UNNotificationAction(
            identifier: "SET_CUSTOM_FOCUS_ACTION",
            title: "🎯 Custom Focus Time",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "DEEP_FOCUS_COMPLETE",
            actions: [focusAnotherHourAction, take15BreakAction, showSessionStatsAction, setCustomFocusAction],
            intentIdentifiers: [],
            options: []
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
    
    // MARK: - Break Timer System
    private func startBreakTimer(duration: TimeInterval = 900) { // Default 15 minutes
        stopBreakTimer() // Stop any existing timer
        
        isBreakTimerActive = true
        breakTimerStartTime = Date()
        
        print("☕ FastSwitch: Iniciando timer de descanso - \(Int(duration / 60))min")
        
        breakTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.showBreakTimerCompleteNotification()
        }
        
        // Update menu to show break timer status
        updateMenuItems(sessionDuration: getCurrentSessionDuration())
    }
    
    private func stopBreakTimer() {
        breakTimer?.invalidate()
        breakTimer = nil
        isBreakTimerActive = false
        breakTimerStartTime = nil
        print("⏹️ FastSwitch: Timer de descanso detenido")
        
        // Update menu
        updateMenuItems(sessionDuration: getCurrentSessionDuration())
    }
    
    private func getBreakTimerRemaining() -> TimeInterval {
        guard let startTime = breakTimerStartTime, isBreakTimerActive else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, 900 - elapsed) // Assuming 15min default
    }
    
    private func showBreakTimerCompleteNotification() {
        print("⏰ FastSwitch: Timer de descanso completado")
        isBreakTimerActive = false
        breakTimerStartTime = nil
        
        let content = UNMutableNotificationContent()
        content.title = "☕ Break Time Complete!"
        content.body = "🎉 Your break is over!\n\n🏃 Ready to get back to work?\n\n💪 You've got this!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Blow.aiff"))
        content.badge = 1
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "BREAK_TIMER_COMPLETE"
        
        // Add action buttons
        let backToWorkAction = UNNotificationAction(
            identifier: "BACK_TO_WORK_ACTION",
            title: "🏃 Back to Work",
            options: []
        )
        
        let extendBreakAction = UNNotificationAction(
            identifier: "EXTEND_BREAK_ACTION",
            title: "☕ +5 Minutes",
            options: []
        )
        
        let showDashboardAction = UNNotificationAction(
            identifier: "SHOW_DASHBOARD_ACTION",
            title: "📊 Show Dashboard",
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: "BREAK_TIMER_COMPLETE",
            actions: [backToWorkAction, extendBreakAction, showDashboardAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "break-timer-complete-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando notificación break timer: \(error)")
            } else {
                print("✅ FastSwitch: Notificación break timer enviada")
            }
        }
    }
    
    // MARK: - Custom Focus Duration
    private func setCustomFocusDuration(_ duration: TimeInterval) {
        customFocusDuration = duration
        print("🎯 FastSwitch: Duración personalizada de focus configurada: \(Int(duration / 60))min")
    }
    
    private func startCustomFocusSession(duration: TimeInterval) {
        setCustomFocusDuration(duration)
        
        // If deep focus is already active, restart with new duration
        if isDeepFocusEnabled {
            disableDeepFocus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.enableDeepFocus()
            }
        } else {
            enableDeepFocus()
        }
    }
    
    private func showCustomFocusDurationOptions() {
        // For now, we'll provide some preset options
        // In a full implementation, this could show a more complex UI
        let options = [
            (duration: 1800.0, title: "30 minutes"),   // 30 min
            (duration: 2700.0, title: "45 minutes"),   // 45 min  
            (duration: 3600.0, title: "60 minutes"),   // 60 min
            (duration: 5400.0, title: "90 minutes"),   // 90 min
            (duration: 7200.0, title: "120 minutes")   // 120 min
        ]
        
        // For simplicity, default to 45 minutes for now
        // In a full implementation, this could show a selection UI
        startCustomFocusSession(duration: 2700) // 45 minutes
        
        print("🎯 FastSwitch: Iniciando sesión personalizada de 45 minutos")
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
    
    // MARK: - Persistent Storage
    private func loadUsageHistory() {
        if let data = UserDefaults.standard.data(forKey: usageHistoryKey),
           let history = try? JSONDecoder().decode(UsageHistory.self, from: data) {
            usageHistory = history
            print("📂 FastSwitch: Historial de uso cargado - \(history.dailyData.count) días")
        } else {
            usageHistory = UsageHistory()
            print("📂 FastSwitch: Iniciando nuevo historial de uso")
        }
    }
    
    private func saveUsageHistory() {
        do {
            let data = try JSONEncoder().encode(usageHistory)
            UserDefaults.standard.set(data, forKey: usageHistoryKey)
            print("💾 FastSwitch: Historial guardado - \(usageHistory.dailyData.count) días")
        } catch {
            print("❌ FastSwitch: Error guardando historial: \(error)")
        }
    }
    
    private func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func initializeTodayData() {
        let todayKey = getTodayKey()
        if usageHistory.dailyData[todayKey] == nil {
            usageHistory.dailyData[todayKey] = DailyUsageData(date: Date())
            print("📅 FastSwitch: Inicializando datos para hoy: \(todayKey)")
        }
    }
    
    private func saveTodayData() {
        let todayKey = getTodayKey()
        guard var todayData = usageHistory.dailyData[todayKey] else {
            print("⚠️ FastSwitch: No hay datos de hoy para guardar")
            return
        }
        
        // Update today's data with current session info
        todayData.totalSessionTime = getCurrentSessionDuration()
        todayData.appUsage = appUsageToday
        todayData.breaksTaken = breaksTaken
        todayData.continuousWorkSessions = continuousWorkSessions
        todayData.longestContinuousSession = longestContinuousSession
        todayData.totalBreakTime = totalBreakTime
        todayData.callTime = currentDayCallTime
        
        // Add current deep focus session if active
        if isDeepFocusEnabled, let startTime = deepFocusStartTime {
            let duration = Date().timeIntervalSince(startTime)
            todayData.deepFocusSessions.append(SessionRecord(start: startTime, duration: duration))
        }
        
        // Add current continuous session if active
        if let sessionStart = currentContinuousSessionStart {
            let duration = Date().timeIntervalSince(sessionStart)
            todayData.continuousWorkSessions.append(SessionRecord(start: sessionStart, duration: duration))
            if duration > todayData.longestContinuousSession {
                todayData.longestContinuousSession = duration
            }
        }
        
        usageHistory.dailyData[todayKey] = todayData
        saveUsageHistory()
        
        print("💾 FastSwitch: Datos de hoy guardados")
    }
    
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
        
        // Track app usage
        trackAppUsage()
        
        // Check if user is in a call
        updateCallStatus()
        
        let effectiveIdleThreshold = isInCall ? callIdleThreshold : idleThreshold
        let sessionDuration = getCurrentSessionDuration()
        
        print("🔍 FastSwitch: Idle tiempo: \(Int(minIdleTime))s (mouse: \(Int(idleTime))s, teclado: \(Int(keyboardIdleTime))s)")
        print("📞 FastSwitch: En llamada: \(isInCall) (manual: \(manualCallToggle))")
        print("⏰ FastSwitch: Sesión actual: \(Int(sessionDuration))s (\(Int(sessionDuration/60))min)")
        
        // Debug: Next notification countdown
        debugNextNotificationCountdown(sessionDuration: sessionDuration)
        
        if let frontApp = currentFrontApp {
            print("📱 FastSwitch: App frontal: \(frontApp)")
        }
        
        if minIdleTime < effectiveIdleThreshold {
            // User is active
            lastActivityTime = currentTime
            print("✅ FastSwitch: Usuario activo (umbral: \(Int(effectiveIdleThreshold))s)")
            
            // Handle continuous session tracking
            if isCurrentlyOnBreak {
                // User was on break and is now active - end break
                endBreak()
            }
            
            if currentContinuousSessionStart == nil {
                // Start new continuous session
                startContinuousSession()
            }
            
            // Calculate session time and check for notifications
            if let startTime = sessionStartTime {
                let sessionDuration = currentTime.timeIntervalSince(startTime)
                checkForBreakNotification(sessionDuration: sessionDuration)
                updateStatusBarTitle(sessionDuration: sessionDuration)
            }
        } else {
            // User is idle - start break if not already on one
            print("😴 FastSwitch: Usuario inactivo (umbral: \(Int(effectiveIdleThreshold))s)")
            
            if !isCurrentlyOnBreak {
                startBreak()
            }
            
            updateStatusBarTitle(sessionDuration: getCurrentSessionDuration())
        }
        
        // Periodic data saving (every minute when user is active)
        if Int(sessionDuration) % 60 == 0 && Int(sessionDuration) > 0 {
            saveTodayData()
        }
        
        print("---")
    }
    
    private func debugNextNotificationCountdown(sessionDuration: TimeInterval) {
        guard notificationsEnabled else {
            print("🔕 DEBUG: Notificaciones deshabilitadas")
            return
        }
        
        // Find next notification interval
        var nextNotification: TimeInterval?
        var nextIndex: Int?
        
        for (index, interval) in notificationIntervals.enumerated() {
            if !sentNotificationIntervals.contains(interval) && sessionDuration < interval {
                nextNotification = interval
                nextIndex = index
                break
            }
        }
        
        if let next = nextNotification, let index = nextIndex {
            let timeLeft = next - sessionDuration
            let minutesLeft = Int(timeLeft / 60)
            let secondsLeft = Int(timeLeft.truncatingRemainder(dividingBy: 60))
            
            print("🔔 DEBUG: Próxima notificación #\(index + 1) en \(minutesLeft):\(String(format: "%02d", secondsLeft)) (intervalo: \(Int(next/60))min)")
            
            // Show progress bar in debug
            let progress = sessionDuration / next
            let progressBars = Int(progress * 20) // 20 character progress bar
            let progressString = String(repeating: "█", count: progressBars) + String(repeating: "░", count: 20 - progressBars)
            print("📊 DEBUG: Progreso [\(progressString)] \(Int(progress * 100))%")
        } else {
            // Check if all notifications have been sent
            let allSent = notificationIntervals.allSatisfy { sentNotificationIntervals.contains($0) }
            if allSent {
                print("✅ DEBUG: Todas las notificaciones enviadas para esta sesión")
            } else {
                print("⚠️ DEBUG: No hay próximas notificaciones programadas")
            }
        }
        
        // Debug break timer status
        if isBreakTimerActive, let startTime = breakTimerStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, 900 - elapsed) // Assuming 15min default
            let minutesLeft = Int(remaining / 60)
            let secondsLeft = Int(remaining.truncatingRemainder(dividingBy: 60))
            print("☕ DEBUG: Break timer activo - Quedan \(minutesLeft):\(String(format: "%02d", secondsLeft))")
        }
        
        // Debug deep focus timer status
        if isDeepFocusEnabled, let startTime = deepFocusStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, customFocusDuration - elapsed)
            let minutesLeft = Int(remaining / 60)
            let secondsLeft = Int(remaining.truncatingRemainder(dividingBy: 60))
            print("🧘 DEBUG: Deep Focus activo - Quedan \(minutesLeft):\(String(format: "%02d", secondsLeft)) (\(Int(customFocusDuration/60))min total)")
        }
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
            
            // Track call time
            if isInCall {
                // Starting a call
                callStartTime = Date()
            } else if let startTime = callStartTime {
                // Ending a call
                let callDuration = Date().timeIntervalSince(startTime)
                currentDayCallTime += callDuration
                callStartTime = nil
                print("📞 FastSwitch: Llamada terminada - Duración: \(Int(callDuration / 60))m")
            }
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
                print("🔔 DEBUG: ✅ NOTIFICACIÓN ENVIADA! Intervalo alcanzado: \(Int(interval/60))min")
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
                print("⚠️ DEBUG: ⏰ PRÓXIMA NOTIFICACIÓN MUY CERCA! \(timeLeft)s restantes")
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
        let startBreakAction = UNNotificationAction(
            identifier: "START_BREAK_ACTION",
            title: "☕ Start 15min Break",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION", 
            title: "⏰ Snooze 5min",
            options: []
        )
        
        let keepWorkingAction = UNNotificationAction(
            identifier: "KEEP_WORKING_ACTION",
            title: "🏃 Keep Working",
            options: []
        )
        
        let showStatsAction = UNNotificationAction(
            identifier: "SHOW_STATS_ACTION",
            title: "📊 Show Stats",
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: "BREAK_REMINDER",
            actions: [startBreakAction, keepWorkingAction, snoozeAction, showStatsAction],
            intentIdentifiers: [],
            options: []
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
    
    // MARK: - App Tracking
    private func getCurrentFrontApp() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return frontApp.bundleIdentifier ?? frontApp.localizedName ?? "Unknown"
    }
    
    private func trackAppUsage() {
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastAppCheckTime)
        
        // Only track if less than 10 seconds elapsed (avoid huge gaps from sleep/inactive periods)
        if timeElapsed < 10, let currentApp = currentFrontApp {
            appUsageToday[currentApp, default: 0] += timeElapsed
        }
        
        // Update current front app
        let newFrontApp = getCurrentFrontApp()
        if newFrontApp != currentFrontApp {
            print("📱 FastSwitch: App changed: \(currentFrontApp ?? "nil") → \(newFrontApp ?? "nil")")
            currentFrontApp = newFrontApp
        }
        
        lastAppCheckTime = now
    }
    
    // MARK: - Break and Session Tracking
    private func startBreak() {
        guard !isCurrentlyOnBreak else { return }
        
        isCurrentlyOnBreak = true
        breakStartTime = Date()
        print("☕ FastSwitch: Iniciando descanso")
        
        // End current continuous session if there is one
        if let sessionStart = currentContinuousSessionStart {
            let duration = Date().timeIntervalSince(sessionStart)
            continuousWorkSessions.append(SessionRecord(start: sessionStart, duration: duration))
            
            // Update longest session if needed
            if duration > longestContinuousSession {
                longestContinuousSession = duration
            }
            
            let minutes = Int(duration / 60)
            print("🏁 FastSwitch: Sesión continua terminada: \(minutes)m")
            
            currentContinuousSessionStart = nil
        }
    }
    
    private func endBreak() {
        guard isCurrentlyOnBreak, let breakStart = breakStartTime else { return }
        
        let breakDuration = Date().timeIntervalSince(breakStart)
        breaksTaken.append(SessionRecord(start: breakStart, duration: breakDuration))
        totalBreakTime += breakDuration
        
        let minutes = Int(breakDuration / 60)
        print("✅ FastSwitch: Descanso terminado: \(minutes)m")
        
        isCurrentlyOnBreak = false
        breakStartTime = nil
    }
    
    private func startContinuousSession() {
        guard currentContinuousSessionStart == nil else { return }
        
        currentContinuousSessionStart = Date()
        print("🚀 FastSwitch: Iniciando sesión continua")
    }
    
    private func getCurrentContinuousSessionDuration() -> TimeInterval {
        guard let sessionStart = currentContinuousSessionStart else { return 0 }
        return Date().timeIntervalSince(sessionStart)
    }
    
    // MARK: - Daily Dashboard
    private func generateDashboard() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        
        let today = formatter.string(from: Date())
        var dashboard = "📊 Daily Usage Report - \(today)\n\n"
        
        // Total session time
        let totalSession = getCurrentSessionDuration()
        let sessionHours = Int(totalSession) / 3600
        let sessionMinutes = Int(totalSession) % 3600 / 60
        dashboard += "⏰ Total Work Session: \(sessionHours)h \(sessionMinutes)m\n\n"
        
        // App usage breakdown
        if !appUsageToday.isEmpty {
            dashboard += "📱 App Usage Breakdown:\n"
            
            // Calculate total usage time for percentage calculations
            let totalAppTime = appUsageToday.values.reduce(0, +)
            
            // Sort apps by usage time
            let sortedApps = appUsageToday.sorted { $0.value > $1.value }
            
            for (app, time) in sortedApps.prefix(10) { // Top 10 apps
                let hours = Int(time) / 3600
                let minutes = Int(time) % 3600 / 60
                let appName = getAppDisplayName(from: app)
                
                // Calculate percentage
                let percentage = totalAppTime > 0 ? (time / totalAppTime) * 100 : 0
                let percentageStr = String(format: "%.1f%%", percentage)
                
                if hours > 0 {
                    dashboard += "  • \(appName): \(hours)h \(minutes)m (\(percentageStr))\n"
                } else if minutes > 0 {
                    dashboard += "  • \(appName): \(minutes)m (\(percentageStr))\n"
                } else {
                    dashboard += "  • \(appName): <1m (\(percentageStr))\n"
                }
            }
            
            // Show total tracked time
            let totalHours = Int(totalAppTime) / 3600
            let totalMinutes = Int(totalAppTime) % 3600 / 60
            if totalHours > 0 {
                dashboard += "\n📊 Total App Time Tracked: \(totalHours)h \(totalMinutes)m\n"
            } else {
                dashboard += "\n📊 Total App Time Tracked: \(totalMinutes)m\n"
            }
        } else {
            dashboard += "📱 No app usage data recorded today\n"
        }
        
        // Deep Focus sessions
        dashboard += "\n🧘 Deep Focus: "
        if isDeepFocusEnabled {
            if let startTime = deepFocusStartTime {
                let focusTime = Date().timeIntervalSince(startTime)
                let focusMinutes = Int(focusTime / 60)
                dashboard += "Currently active (\(focusMinutes)m)"
            } else {
                dashboard += "Currently active"
            }
        } else {
            dashboard += "Not active today"
        }
        
        // Call time
        dashboard += "\n📞 In Calls: "
        if isInCall {
            dashboard += "Currently in a call"
        } else {
            dashboard += "No active calls"
        }
        
        // Break and continuous session analysis
        dashboard += "\n\n💪 Work Pattern Analysis:"
        
        // Current status
        if isCurrentlyOnBreak {
            if let breakStart = breakStartTime {
                let currentBreakTime = Date().timeIntervalSince(breakStart)
                let breakMinutes = Int(currentBreakTime / 60)
                dashboard += "\n☕ Currently on break (\(breakMinutes)m)"
            } else {
                dashboard += "\n☕ Currently on break"
            }
        } else if let sessionStart = currentContinuousSessionStart {
            let currentSessionTime = Date().timeIntervalSince(sessionStart)
            let sessionMinutes = Int(currentSessionTime / 60)
            dashboard += "\n🏃 Current continuous session: \(sessionMinutes)m"
        } else {
            dashboard += "\n⏸️ Currently inactive"
        }
        
        // Break statistics
        let breakCount = breaksTaken.count
        if breakCount > 0 {
            let totalBreakHours = Int(totalBreakTime) / 3600
            let totalBreakMinutes = Int(totalBreakTime) % 3600 / 60
            let averageBreakTime = totalBreakTime / Double(breakCount)
            let avgBreakMinutes = Int(averageBreakTime / 60)
            
            if totalBreakHours > 0 {
                dashboard += "\n☕ Breaks taken: \(breakCount) (\(totalBreakHours)h \(totalBreakMinutes)m total, ~\(avgBreakMinutes)m avg)"
            } else {
                dashboard += "\n☕ Breaks taken: \(breakCount) (\(totalBreakMinutes)m total, ~\(avgBreakMinutes)m avg)"
            }
        } else {
            dashboard += "\n☕ No breaks taken today"
        }
        
        // Continuous session statistics
        let sessionCount = continuousWorkSessions.count
        if sessionCount > 0 {
            let longestHours = Int(longestContinuousSession) / 3600
            let longestMinutes = Int(longestContinuousSession) % 3600 / 60
            
            // Calculate average session length
            let totalSessionTime = continuousWorkSessions.reduce(0) { $0 + $1.duration }
            let averageSessionTime = totalSessionTime / Double(sessionCount)
            let avgSessionMinutes = Int(averageSessionTime / 60)
            
            if longestHours > 0 {
                dashboard += "\n🏃 Work sessions: \(sessionCount) (longest: \(longestHours)h \(longestMinutes)m, avg: \(avgSessionMinutes)m)"
            } else {
                dashboard += "\n🏃 Work sessions: \(sessionCount) (longest: \(longestMinutes)m, avg: \(avgSessionMinutes)m)"
            }
            
            // Warning for long sessions without breaks
            if longestContinuousSession > 3600 { // More than 1 hour
                dashboard += "\n⚠️ Consider taking more frequent breaks for health!"
            }
        } else {
            dashboard += "\n🏃 No completed work sessions today"
        }
        
        // Include current session in longest calculation for warning
        let currentSessionDuration = getCurrentContinuousSessionDuration()
        if currentSessionDuration > 3600 {
            let currentHours = Int(currentSessionDuration) / 3600
            let currentMinutes = Int(currentSessionDuration) % 3600 / 60
            dashboard += "\n⚠️ Current session is \(currentHours)h \(currentMinutes)m - time for a break!"
        } else if currentSessionDuration > 2700 { // 45 minutes
            let currentMinutes = Int(currentSessionDuration / 60)
            dashboard += "\n💡 Current session: \(currentMinutes)m - consider a break soon"
        }
        
        return dashboard
    }
    
    // MARK: - Report Generation
    private func generateWeeklyReport() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        var report = "📊 Weekly Usage Report\n"
        report += "📅 \(formatter.string(from: weekAgo)) - \(formatter.string(from: today))\n\n"
        
        // Get data for the last 7 days
        let weekData = getDataForDateRange(from: weekAgo, to: today)
        
        if weekData.isEmpty {
            report += "📭 No data available for this week.\n"
            return report
        }
        
        // Calculate totals
        let totalSessionTime = weekData.reduce(0) { $0 + $1.totalSessionTime }
        let totalBreakTime = weekData.reduce(0) { $0 + $1.totalBreakTime }
        let totalCallTime = weekData.reduce(0) { $0 + $1.callTime }
        let totalDays = weekData.count
        
        // Session time summary
        let hours = Int(totalSessionTime) / 3600
        let minutes = Int(totalSessionTime) % 3600 / 60
        report += "⏰ Total Work Time: \(hours)h \(minutes)m across \(totalDays) days\n"
        
        if totalDays > 0 {
            let avgDaily = totalSessionTime / Double(totalDays)
            let avgHours = Int(avgDaily) / 3600
            let avgMinutes = Int(avgDaily) % 3600 / 60
            report += "📈 Average Daily: \(avgHours)h \(avgMinutes)m\n"
        }
        
        // Break analysis
        let breakHours = Int(totalBreakTime) / 3600
        let breakMinutes = Int(totalBreakTime) % 3600 / 60
        report += "☕ Total Breaks: \(breakHours)h \(breakMinutes)m\n"
        
        // Call time
        let callHours = Int(totalCallTime) / 3600
        let callMinutesPart = Int(totalCallTime) % 3600 / 60
        report += "📞 Call Time: \(callHours)h \(callMinutesPart)m\n"
        
        // Top apps aggregation
        var aggregatedAppUsage: [String: TimeInterval] = [:]
        for dayData in weekData {
            for (app, time) in dayData.appUsage {
                aggregatedAppUsage[app, default: 0] += time
            }
        }
        
        if !aggregatedAppUsage.isEmpty {
            report += "\n📱 Top Apps This Week:\n"
            let sortedApps = aggregatedAppUsage.sorted { $0.value > $1.value }
            for (app, time) in sortedApps.prefix(5) {
                let appHours = Int(time) / 3600
                let appMinutes = Int(time) % 3600 / 60
                let appName = getAppDisplayName(from: app)
                
                if appHours > 0 {
                    report += "  • \(appName): \(appHours)h \(appMinutes)m\n"
                } else {
                    report += "  • \(appName): \(appMinutes)m\n"
                }
            }
        }
        
        // Deep Focus analysis
        let allDeepFocusSessions = weekData.flatMap { $0.deepFocusSessions }
        if !allDeepFocusSessions.isEmpty {
            let totalDeepFocusTime = allDeepFocusSessions.reduce(0) { $0 + $1.duration }
            let focusHours = Int(totalDeepFocusTime) / 3600
            let focusMinutes = Int(totalDeepFocusTime) % 3600 / 60
            report += "\n🧘 Deep Focus: \(allDeepFocusSessions.count) sessions, \(focusHours)h \(focusMinutes)m total\n"
        }
        
        return report
    }
    
    private func generateYearlyReport() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        let currentYear = formatter.string(from: Date())
        
        var report = "📊 Yearly Usage Report - \(currentYear)\n\n"
        
        // Get data for the current year
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: calendar.component(.year, from: Date())))!
        let yearData = getDataForDateRange(from: startOfYear, to: Date())
        
        if yearData.isEmpty {
            report += "📭 No data available for this year.\n"
            return report
        }
        
        // Calculate totals
        let totalSessionTime = yearData.reduce(0) { $0 + $1.totalSessionTime }
        let totalBreakTime = yearData.reduce(0) { $0 + $1.totalBreakTime }
        let totalCallTime = yearData.reduce(0) { $0 + $1.callTime }
        let totalDays = yearData.count
        
        // Session time summary
        let hours = Int(totalSessionTime) / 3600
        let minutes = Int(totalSessionTime) % 3600 / 60
        report += "⏰ Total Work Time: \(hours)h \(minutes)m across \(totalDays) days\n"
        
        if totalDays > 0 {
            let avgDaily = totalSessionTime / Double(totalDays)
            let avgHours = Int(avgDaily) / 3600
            let avgMinutes = Int(avgDaily) % 3600 / 60
            report += "📈 Average Daily: \(avgHours)h \(avgMinutes)m\n"
        }
        
        // Monthly breakdown
        report += "\n📅 Monthly Breakdown:\n"
        let monthlyData = groupDataByMonth(yearData)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        
        for (month, data) in monthlyData.sorted(by: { $0.key < $1.key }) {
            let monthTime = data.reduce(0) { $0 + $1.totalSessionTime }
            let monthHours = Int(monthTime) / 3600
            let monthMinutes = Int(monthTime) % 3600 / 60
            let monthName = monthFormatter.string(from: month)
            report += "  • \(monthName): \(monthHours)h \(monthMinutes)m (\(data.count) days)\n"
        }
        
        // Top apps for the year
        var aggregatedAppUsage: [String: TimeInterval] = [:]
        for dayData in yearData {
            for (app, time) in dayData.appUsage {
                aggregatedAppUsage[app, default: 0] += time
            }
        }
        
        if !aggregatedAppUsage.isEmpty {
            report += "\n📱 Top Apps This Year:\n"
            let sortedApps = aggregatedAppUsage.sorted { $0.value > $1.value }
            for (app, time) in sortedApps.prefix(10) {
                let appHours = Int(time) / 3600
                let appMinutes = Int(time) % 3600 / 60
                let appName = getAppDisplayName(from: app)
                
                if appHours > 0 {
                    report += "  • \(appName): \(appHours)h \(appMinutes)m\n"
                } else {
                    report += "  • \(appName): \(appMinutes)m\n"
                }
            }
        }
        
        // Deep Focus yearly stats
        let allDeepFocusSessions = yearData.flatMap { $0.deepFocusSessions }
        if !allDeepFocusSessions.isEmpty {
            let totalDeepFocusTime = allDeepFocusSessions.reduce(0) { $0 + $1.duration }
            let focusHours = Int(totalDeepFocusTime) / 3600
            let focusMinutes = Int(totalDeepFocusTime) % 3600 / 60
            report += "\n🧘 Deep Focus This Year: \(allDeepFocusSessions.count) sessions, \(focusHours)h \(focusMinutes)m total\n"
        }
        
        return report
    }
    
    private func getDataForDateRange(from startDate: Date, to endDate: Date) -> [DailyUsageData] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var result: [DailyUsageData] = []
        let calendar = Calendar.current
        var currentDate = startDate
        
        while currentDate <= endDate {
            let dateKey = formatter.string(from: currentDate)
            if let dayData = usageHistory.dailyData[dateKey] {
                result.append(dayData)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return result
    }
    
    private func groupDataByMonth(_ data: [DailyUsageData]) -> [Date: [DailyUsageData]] {
        let calendar = Calendar.current
        var monthlyData: [Date: [DailyUsageData]] = [:]
        
        for dayData in data {
            let month = calendar.dateInterval(of: .month, for: dayData.date)!.start
            monthlyData[month, default: []].append(dayData)
        }
        
        return monthlyData
    }
    
    private func getAppDisplayName(from identifier: String) -> String {
        // Try to get user-friendly app name
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           let bundle = Bundle(url: url),
           let displayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                             bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                             bundle.localizedInfoDictionary?["CFBundleName"] as? String ??
                             bundle.infoDictionary?["CFBundleName"] as? String {
            return displayName
        }
        
        // Fallback to bundle identifier with some cleanup
        return identifier.replacingOccurrences(of: "com.", with: "")
                        .replacingOccurrences(of: "app.", with: "")
                        .components(separatedBy: ".").last ?? identifier
    }
    
    private func showDailyDashboard() {
        print("📊 FastSwitch: Mostrando dashboard diario")
        
        let content = UNMutableNotificationContent()
        content.title = "📊 Daily Work Summary"
        content.body = generateDashboard()
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Submarine.aiff"))
        content.badge = 1
        content.interruptionLevel = .active
        content.categoryIdentifier = "DAILY_DASHBOARD"
        
        // Add action buttons
        let weeklyReportAction = UNNotificationAction(
            identifier: "WEEKLY_REPORT_ACTION",
            title: "📈 Weekly Report",
            options: [.foreground]
        )
        
        let exportDataAction = UNNotificationAction(
            identifier: "EXPORT_DATA_ACTION",
            title: "💾 Export Data",
            options: [.foreground]
        )
        
        let resetSessionAction = UNNotificationAction(
            identifier: "DASHBOARD_RESET_ACTION",
            title: "🔄 Reset Session",
            options: []
        )
        
        let setGoalAction = UNNotificationAction(
            identifier: "SET_GOAL_ACTION",
            title: "🎯 Set Tomorrow's Goal",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "DAILY_DASHBOARD",
            actions: [weeklyReportAction, exportDataAction, resetSessionAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "daily-dashboard-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando dashboard: \(error)")
            } else {
                print("✅ FastSwitch: Dashboard diario enviado")
            }
        }
    }
    
    private func scheduleDailyDashboard() {
        // Cancel existing timer
        dashboardTimer?.invalidate()
        
        let calendar = Calendar.current
        let now = Date()
        
        // Create target time: today at 18:30
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 18
        components.minute = 30
        components.second = 0
        
        guard let targetTime = calendar.date(from: components) else { return }
        
        // If it's already past 18:30 today, schedule for tomorrow
        let finalTargetTime = targetTime < now ? 
            calendar.date(byAdding: .day, value: 1, to: targetTime)! : targetTime
        
        let timeInterval = finalTargetTime.timeIntervalSince(now)
        
        print("📊 FastSwitch: Dashboard programado para \(finalTargetTime)")
        
        dashboardTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.hasShownDashboardToday {
                self.showDailyDashboard()
                self.hasShownDashboardToday = true
            }
            // Reset for next day and schedule
            self.hasShownDashboardToday = false
            self.scheduleDailyDashboard()
        }
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
        
        // Reset break and session tracking
        breaksTaken.removeAll()
        continuousWorkSessions.removeAll()
        currentContinuousSessionStart = Date()
        isCurrentlyOnBreak = false
        breakStartTime = nil
        longestContinuousSession = 0
        totalBreakTime = 0
        
        print("🔄 FastSwitch: Sesión y tracking de descansos reiniciados")
    }
    
    @objc private func showDashboardManually() {
        print("📊 FastSwitch: Dashboard solicitado manualmente")
        showDailyDashboard()
    }
    
    @objc private func showWeeklyReport() {
        print("📈 FastSwitch: Reporte semanal solicitado")
        saveTodayData() // Ensure current data is saved
        showReport(title: "📈 Weekly Report", content: generateWeeklyReport(), identifier: "weekly-report")
    }
    
    @objc private func showYearlyReport() {
        print("📅 FastSwitch: Reporte anual solicitado")
        saveTodayData() // Ensure current data is saved
        showReport(title: "📅 Yearly Report", content: generateYearlyReport(), identifier: "yearly-report")
    }
    
    private func showReport(title: String, content: String, identifier: String) {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = title
        notificationContent.body = content
        notificationContent.sound = UNNotificationSound(named: UNNotificationSoundName("Submarine.aiff"))
        notificationContent.badge = 1
        notificationContent.interruptionLevel = .active
        notificationContent.categoryIdentifier = "USAGE_REPORT"
        
        // Add action button
        let okAction = UNNotificationAction(
            identifier: "REPORT_OK_ACTION",
            title: "✅ Got it!",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "USAGE_REPORT",
            actions: [okAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "\(identifier)-\(Int(Date().timeIntervalSince1970))",
            content: notificationContent,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando reporte: \(error)")
            } else {
                print("✅ FastSwitch: Reporte \(identifier) enviado")
            }
        }
    }
    
    @objc private func exportUsageData() {
        print("💾 FastSwitch: Exportando datos de uso")
        saveTodayData() // Ensure current data is saved
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Usage Data"
        savePanel.nameFieldStringValue = "FastSwitch-Usage-Data-\(getTodayKey()).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let data = try JSONEncoder().encode(self.usageHistory)
                    try data.write(to: url)
                    
                    // Show success notification
                    let content = UNMutableNotificationContent()
                    content.title = "💾 Export Complete"
                    content.body = "Usage data exported successfully to:\n\(url.path)\n\n📊 \(self.usageHistory.dailyData.count) days of data exported."
                    content.sound = UNNotificationSound(named: UNNotificationSoundName("Glass.aiff"))
                    content.interruptionLevel = .active
                    
                    let request = UNNotificationRequest(
                        identifier: "export-success-\(Int(Date().timeIntervalSince1970))",
                        content: content,
                        trigger: nil
                    )
                    
                    UNUserNotificationCenter.current().add(request)
                    print("✅ FastSwitch: Datos exportados a: \(url.path)")
                } catch {
                    print("❌ FastSwitch: Error exportando datos: \(error)")
                    
                    // Show error notification
                    let content = UNMutableNotificationContent()
                    content.title = "❌ Export Failed"
                    content.body = "Failed to export usage data:\n\(error.localizedDescription)"
                    content.sound = UNNotificationSound(named: UNNotificationSoundName("Basso.aiff"))
                    content.interruptionLevel = .active
                    
                    let request = UNNotificationRequest(
                        identifier: "export-error-\(Int(Date().timeIntervalSince1970))",
                        content: content,
                        trigger: nil
                    )
                    
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
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
        print("🧪 DEBUG: MODO TESTING ACTIVADO - Próximas notificaciones en: 1min, 5min, 10min")
    }
    
    @objc private func setNotificationInterval45() {
        notificationIntervals = [2700, 5400, 8100] // 45min, 1.5hr, 2.25hr
        notificationsEnabled = true
        currentNotificationMode = .interval45
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        print("⏰ FastSwitch: Configurado intervalos 45min")
        print("⏰ DEBUG: INTERVALOS 45MIN - Próximas notificaciones en: 45min, 90min, 135min")
    }
    
    @objc private func setNotificationInterval60() {
        notificationIntervals = [3600, 7200, 10800] // 1hr, 2hr, 3hr
        notificationsEnabled = true
        currentNotificationMode = .interval60
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        print("⏰ FastSwitch: Configurado intervalos 60min")
        print("⏰ DEBUG: INTERVALOS 60MIN - Próximas notificaciones en: 60min, 120min, 180min")
    }
    
    @objc private func setNotificationInterval90() {
        notificationIntervals = [5400, 10800, 16200] // 1.5hr, 3hr, 4.5hr
        notificationsEnabled = true
        currentNotificationMode = .interval90
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        print("⏰ FastSwitch: Configurado intervalos 90min")
        print("⏰ DEBUG: INTERVALOS 90MIN - Próximas notificaciones en: 90min, 180min, 270min")
    }
    
    @objc private func disableNotifications() {
        notificationsEnabled = false
        currentNotificationMode = .disabled
        updateConfigurationMenuState()
        print("🔕 FastSwitch: Notificaciones deshabilitadas")
        print("🔕 DEBUG: NOTIFICACIONES DESHABILITADAS - No habrá recordatorios")
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
            
        case "DASHBOARD_OK_ACTION":
            print("📊 FastSwitch: Usuario confirmó dashboard diario")
            NSApp.dockTile.badgeLabel = nil
            
        case "DASHBOARD_RESET_ACTION":
            print("🔄 FastSwitch: Usuario solicitó reset desde dashboard")
            resetSession()
            NSApp.dockTile.badgeLabel = nil
            
        case "REPORT_OK_ACTION":
            print("📊 FastSwitch: Usuario confirmó reporte")
            NSApp.dockTile.badgeLabel = nil
            
        // New Break Reminder Actions
        case "START_BREAK_ACTION":
            print("☕ FastSwitch: Usuario inició descanso desde notificación")
            startBreakTimer(duration: 900) // 15 minutes
            stopStickyBreakNotifications()
            NSApp.dockTile.badgeLabel = nil
            
        case "KEEP_WORKING_ACTION":
            print("🏃 FastSwitch: Usuario eligió continuar trabajando")
            // Reset session start time to extend current session
            sessionStartTime = Date()
            sentNotificationIntervals.removeAll()
            stopStickyBreakNotifications()
            NSApp.dockTile.badgeLabel = nil
            
        case "SHOW_STATS_ACTION":
            print("📊 FastSwitch: Usuario solicitó estadísticas desde notificación")
            showDailyDashboard()
            stopStickyBreakNotifications()
            NSApp.dockTile.badgeLabel = nil
            
        // New Deep Focus Actions
        case "FOCUS_ANOTHER_HOUR_ACTION":
            print("🧘 FastSwitch: Usuario eligió continuar focus otra hora")
            stopStickyDeepFocusNotification()
            // Restart with 60 minutes
            setCustomFocusDuration(3600)
            deepFocusTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
                self?.showDeepFocusCompletionNotification()
            }
            NSApp.dockTile.badgeLabel = nil
            
        case "TAKE_15MIN_BREAK_ACTION":
            print("☕ FastSwitch: Usuario eligió tomar descanso de 15min")
            stopStickyDeepFocusNotification()
            if isDeepFocusEnabled {
                toggleDeepFocus() // Disable deep focus
            }
            startBreakTimer(duration: 900) // 15 minutes
            NSApp.dockTile.badgeLabel = nil
            
        case "SHOW_SESSION_STATS_ACTION":
            print("📊 FastSwitch: Usuario solicitó estadísticas de sesión")
            stopStickyDeepFocusNotification()
            showDailyDashboard()
            NSApp.dockTile.badgeLabel = nil
            
        case "SET_CUSTOM_FOCUS_ACTION":
            print("🎯 FastSwitch: Usuario eligió duración personalizada")
            stopStickyDeepFocusNotification()
            showCustomFocusDurationOptions()
            NSApp.dockTile.badgeLabel = nil
            
        // Break Timer Complete Actions
        case "BACK_TO_WORK_ACTION":
            print("🏃 FastSwitch: Usuario volvió al trabajo")
            stopBreakTimer()
            NSApp.dockTile.badgeLabel = nil
            
        case "EXTEND_BREAK_ACTION":
            print("☕ FastSwitch: Usuario extendió descanso 5min")
            startBreakTimer(duration: 300) // 5 more minutes
            NSApp.dockTile.badgeLabel = nil
            
        case "SHOW_DASHBOARD_ACTION":
            print("📊 FastSwitch: Usuario solicitó dashboard desde break timer")
            showDailyDashboard()
            NSApp.dockTile.badgeLabel = nil
            
        // New Dashboard Actions
        case "WEEKLY_REPORT_ACTION":
            print("📈 FastSwitch: Usuario solicitó reporte semanal desde dashboard")
            showWeeklyReport()
            NSApp.dockTile.badgeLabel = nil
            
        case "EXPORT_DATA_ACTION":
            print("💾 FastSwitch: Usuario solicitó exportar datos desde dashboard")
            exportUsageData()
            NSApp.dockTile.badgeLabel = nil
            
        case "SET_GOAL_ACTION":
            print("🎯 FastSwitch: Usuario quiere configurar objetivo")
            // For now, just show a confirmation
            // In a full implementation, this could show a goal-setting interface
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

