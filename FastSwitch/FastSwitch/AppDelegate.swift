import Cocoa
import os.log
import Carbon.HIToolbox
import ApplicationServices
import UserNotifications
import Foundation
import UniformTypeIdentifiers




class AppDelegate: NSObject, NSApplicationDelegate, NotificationManagerDelegate, HotkeyManagerDelegate, AppSwitchingManagerDelegate, PersistenceManagerDelegate, UsageTrackingManagerDelegate, BreakReminderManagerDelegate, WellnessManagerDelegate, MenuBarManagerDelegate, DeepFocusManagerDelegate {
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "AppDelegate")
    // Action delay for double-tap actions
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
    
    // Break sticky notifications (now handled by BreakReminderManager)
    
    // Deep Focus: guardá el último ID para poder limpiarlo (bugfix)
    private var lastDeepFocusNotificationID: String?
    
    // App tracking and dashboard (now handled by UsageTrackingManager)
    private var dashboardTimer: Timer?
    private var hasShownDashboardToday: Bool = false
    
    // Break tracking (now handled by BreakReminderManager)
    
    // Configuration
    private let idleThreshold: TimeInterval = 300 // 5 minutes
    private let callIdleThreshold: TimeInterval = 1800 // 30 minutes
    private let checkInterval: TimeInterval = 5 // 5 seconds para testing
    private var notificationIntervals: [TimeInterval] = [60, 300, 600] // 1min, 5min, 10min para testing
    private var notificationsEnabled: Bool = true
    
    // Track current notification mode (using NotificationMode from DataModels)
    private var currentNotificationMode: NotificationMode = .interval60
    
    // Persistent storage
    private var usageHistory: UsageHistory = UsageHistory()
    private var deepFocusSessionStartTime: Date?
    
    // Break timer system (now handled by BreakReminderManager)
    private var customFocusDuration: TimeInterval = 3600 // Default 60 minutes
    
    // Wellness tracking now fully handled by WellnessManager

    // Break tracking - some properties still needed for backwards compatibility
    private var isCurrentlyOnBreak: Bool = false
    private var breakStartTime: Date?
    private var currentContinuousSessionStart: Date?
    private var breaksTaken: [SessionRecord] = []
    private var totalBreakTime: TimeInterval = 0
    private var continuousWorkSessions: [SessionRecord] = []
    private var longestContinuousSession: TimeInterval = 0
    private var callStartTime: Date?
    private var currentDayCallTime: TimeInterval = 0
    // Break sticky notifications handled by BreakReminderManager

    // Additional tracking properties
    private var currentFrontApp: String?
    private var breakTimerStartTime: Date?
    // (migrated) sticky reminder config now lives in BreakReminderManager

    // Motivational phrases system
    private var motivationalPhrases: [MotivationalPhrase] = []
    private var recentPhrases: [String] = [] // Track recently shown phrases to avoid repetition
    private let maxRecentPhrases = 5
    
    // Mate reduction plan system (now handled by WellnessManager)

    // F-keys → apps/acciones

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if another instance is already running
        let runningApps = NSWorkspace.shared.runningApplications
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        for app in runningApps {
            if app.bundleIdentifier == Bundle.main.bundleIdentifier && app.processIdentifier != currentPID {
                logger.error("⚠️ Another instance is already running, exiting…")
                NSApp.terminate(nil)
                return
            }
        }
        
        logger.info("🚀 Starting up…")
        logger.info("⏱️ Action delay: \(self.actionDelay, privacy: .public)s")
        
        // Menu-bar only (hide Dock & app switcher)
        NSApp.setActivationPolicy(.accessory)

        
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        // Setup managers
        NotificationManager.shared.delegate = self
        HotkeyManager.shared.delegate = self
        AppSwitchingManager.shared.delegate = self
        PersistenceManager.shared.delegate = self
        UsageTrackingManager.shared.delegate = self
        BreakReminderManager.shared.delegate = self
        WellnessManager.shared.delegate = self
        MenuBarManager.shared.delegate = self
        DeepFocusManager.shared.delegate = self

        // Setup menu bar
        MenuBarManager.shared.setupStatusBar()
        // Reflect wallpaper menu state at startup
        MenuBarManager.shared.updateWallpaperMenu(
            isEnabled: AppConfig.wallpaperEnabled,
            intervalMinutes: Int(WallpaperPhraseManager.shared.interval / 60)
        )
        
        // Handle wallpaper menu state
        if !AppConfig.wallpaperEnabled {
            WallpaperPhraseManager.shared.stop()
        }
        
        // Start usage tracking
        UsageTrackingManager.shared.startTracking()
        
        // Load usage history
        usageHistory = PersistenceManager.shared.loadUsageHistory()
        
        // Initialize today's data if needed
        initializeTodayData()
        
        // Schedule daily dashboard
        scheduleDailyDashboard()
        
        // Initialize wellness tracking (managed by WellnessManager)
        // Enable in DEBUG and trigger test questions; keep opt-in in production.
        
        // Load motivational phrases
        loadMotivationalPhrases()
        
        // Wellness features now managed by WellnessManager
        
        // Configure notification intervals and wellness in DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            #if DEBUG
            self.setNotificationIntervalTest()
            WellnessManager.shared.setWellnessEnabled(true)
            WellnessManager.shared.setMateTrackingEnabled(true)
            WellnessManager.shared.setExerciseTrackingEnabled(true)
            WellnessManager.shared.setMoodTrackingEnabled(true)
            WellnessManager.shared.setDailyReflectionEnabled(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                WellnessManager.shared.triggerTestWellnessQuestions()
            }
            #else
            self.setNotificationInterval60()
            #endif
        }

        // Wellness reminders now handled by WellnessManager
        
        // Update initial menu state according to currentNotificationMode
        updateConfigurationMenuState()

        // Hotkeys
        HotkeyManager.shared.registerHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) { 
        // Save today's data before terminating
        saveTodayData()
        if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
        
        HotkeyManager.shared.unregisterHotkeys()
        UsageTrackingManager.shared.stopTracking()
        deepFocusTimer?.invalidate()
        deepFocusNotificationTimer?.invalidate()
        BreakReminderManager.shared.stopStickyBreakReminders()
        dashboardTimer?.invalidate()
        BreakReminderManager.shared.stopBreakTimer()
        // Wellness timers now handled by WellnessManager
    }


    // MARK: - HotkeyManagerDelegate
    func hotkeyManager(_ manager: HotkeyManager, didReceiveAction action: String) {
        if action.hasPrefix("action:") {
            logger.info("🎬 Executing action: \(action)")
            switch action {
            case "action:meet-mic": toggleMeetMic()
            case "action:meet-cam": toggleMeetCam()
            case "action:deep-focus": DeepFocusManager.shared.toggleDeepFocus()
            case "action:insta360-track": toggleInsta360Tracking()
            case "action:dasung-refresh":
                DasungRefresher.shared.refreshPaperlike()
            case "action:paperlike-resolution": togglePaperlikeResolutionToggle()
            case "action:paperlike-optimize": toggleGlobalGrayscale()
            default: break
            }
        } else {
            // Single tap - activate app only
            AppSwitchingManager.shared.activateApp(bundleID: action)
        }
    }
    
    func hotkeyManager(_ manager: HotkeyManager, didReceiveDoubleAction action: String, completion: (() -> Void)?) {
        // Double tap - activate app + in-app action
        AppSwitchingManager.shared.activateAppWithAction(bundleID: action, completion: completion)
    }

    // MARK: - AppSwitchingManagerDelegate
    func appSwitchingManager(_ manager: AppSwitchingManager, needsAppleScript script: String) {
        runAppleScript(script, openPrefsOnError: false)
    }
    
    func appSwitchingManager(_ manager: AppSwitchingManager, needsSpotifyAction action: String) {
        switch action {
        case "playPause":
            playPauseSpotifyWithRetry()
        default:
            break
        }
    }

    // MARK: - Permissions (Chrome / System Events / Spotify) — SAFE
    @objc private func requestAutomationPrompts() {
        AppSwitchingManager.shared.preopenIfNeeded(bundleID: "com.google.Chrome")
        AppSwitchingManager.shared.preopenIfNeeded(bundleID: "com.spotify.client")

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


    // MARK: - Meet (Chrome)
    private func toggleMeetMic() {
        let chrome = "com.google.Chrome"
        logger.info("🎤 F5 pressed - Toggle Meet mic")
        
        // Automatically set call status when using Meet controls
        if chromeFrontTabIsMeet() {
            manualCallToggle = true
            logger.info("🎤 Meet detected, enabling call status")
        }
        
        AppSwitchingManager.shared.activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { 
                self.sendShortcut(letter: "d", command: true) // ⌘D
                self.manualCallToggle = true // Ensure call status is set
                logger.info("🎤 Sent ⌘D to toggle mic")
            }
        }
    }
    private func toggleMeetCam() {
        let chrome = "com.google.Chrome"
        logger.info("📹 F6 pressed - Toggle Meet camera")
        
        // Automatically set call status when using Meet controls
        if chromeFrontTabIsMeet() {
            manualCallToggle = true
            logger.info("📹 Meet detected, enabling call status")
        }
        
        AppSwitchingManager.shared.activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { 
                self.sendShortcut(letter: "e", command: true) // ⌘E
                self.manualCallToggle = true // Ensure call status is set
                logger.info("📹 Sent ⌘E to toggle camera")
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
        if let error { logger.error("AppleScript Chrome URL error: \(error[NSLocalizedDescriptionKey] as? String ?? String(describing: error))") }
        return (result?.booleanValue) ?? false
    }

    // MARK: - Deep Focus (F7)
    private func toggleDeepFocus() {
        isDeepFocusEnabled.toggle()
        logger.info("🧘 Toggle Deep Focus: \(self.isDeepFocusEnabled ? "ON" : "OFF")")
        
        if isDeepFocusEnabled {
            enableDeepFocus()
        } else {
            disableDeepFocus()
        }
        
        // Update menu bar and menu items to show focus status
        updateStatusBarForFocus()
        updateMenuItems(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
    }
    
    private func enableDeepFocus() {
        logger.info("🧘 Activating Deep Focus…")
        
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
        
        logger.info("✅ Deep Focus enabled - macOS + Slack DND, 60min timer started")
    }
    
    private func disableDeepFocus() {
        logger.info("🧘 Deactivating Deep Focus…")
        
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
                if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
            }
            
            logger.info("✅ Deep Focus disabled - macOS + Slack DND off (duration: \(minutes)min)")
            deepFocusSessionStartTime = nil
        }
        
        deepFocusStartTime = nil
    }
    
    private func updateStatusBarForFocus() {
        // Focus status is now handled by MenuBarManager (source of truth: DeepFocusManager)
        MenuBarManager.shared.updateDeepFocusStatus(DeepFocusManager.shared.isEnabled)
    }
    
    private func enableSlackDND() {
        logger.info("🧘 Activating Slack DND…")
        
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
        logger.info("✅ DND command sent to Slack")
    }
    
    private func disableSlackDND() {
        logger.info("🧘 Deactivating Slack DND…")
        
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
        logger.info("✅ Slack DND disabled")
    }
    
    private func showDeepFocusCompletionNotification() {
        logger.info("🧘 60min Deep Focus session completed")
        
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
                self.logger.info("🧘 Sticky notification timer expired after 1 minute")
                timer.invalidate()
                self.deepFocusNotificationTimer = nil
                self.deepFocusNotificationStartTime = nil
            } else {
                // Re-send notification to keep it visible
                self.logger.info("🧘 Re-sending sticky notification (\(Int(elapsed))s elapsed)")
                self.sendDeepFocusNotification()
            }
        }
    }
    
    private func sendDeepFocusNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🧘 Deep Focus Session Complete"
        content.body = "⏰ You've completed 60 minutes of focused work!\n\n🎉 Great job staying focused!\n\n💡 Consider taking a break or continuing your session.\n\n👆 MUST CLICK to dismiss this sticky notification."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Crystal.aiff"))
        content.badge = NSNumber(value: 1)
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
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending Deep Focus notification: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Deep Focus sticky notification sent")
            }
        }
    }
    
    private func stopStickyDeepFocusNotification() {
        logger.info("🧘 Stopping sticky Deep Focus notifications")
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
    
    
    // MARK: - Custom Focus Duration
    private func setCustomFocusDuration(_ duration: TimeInterval) {
        customFocusDuration = duration
        logger.info("🎯 Custom focus duration configured: \(Int(duration / 60))min")
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
        let _ = [
            (duration: 1800.0, title: "30 minutes"),   // 30 min
            (duration: 2700.0, title: "45 minutes"),   // 45 min  
            (duration: 3600.0, title: "60 minutes"),   // 60 min
            (duration: 5400.0, title: "90 minutes"),   // 90 min
            (duration: 7200.0, title: "120 minutes")   // 120 min
        ]
        
        // For simplicity, default to 45 minutes for now
        // In a full implementation, this could show a selection UI
        startCustomFocusSession(duration: 2700) // 45 minutes
        
        logger.info("🎯 Starting custom 45-minute session")
    }
    
    // Wellness scheduling and questions moved to WellnessManager
    
    // MARK: - Wellness Data Recording
    // (migrated) recordMate handled via WellnessManager + delegate
    
    // Mate plan scheduling is managed by WellnessManager
    
    // (migrated) Exercise and wellness persistence now handled via WellnessManager delegate callbacks
    
    // MARK: - Motivational Phrases System
    private func loadMotivationalPhrases() {
        // Try to load from external JSON file first
        if let phrasesFromFile = loadPhrasesFromFile() {
            motivationalPhrases = phrasesFromFile
            logger.info("💡 Loaded phrases from file - count: \(self.motivationalPhrases.count)")
        } else {
            // Fallback to default phrases
            loadDefaultPhrases()
            logger.info("💡 Using default phrases - count: \(self.motivationalPhrases.count)")
        }
    }
    
    private func loadPhrasesFromFile() -> [MotivationalPhrase]? {
        var pathsToTry: [URL] = []
        // 0) User-specified custom path
        if let customPath = UserDefaults.standard.string(forKey: "PhrasesPath"), !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            pathsToTry.append(url)
        }
        
        // 1) Bundle resource
        if let bundleURL = Bundle.main.url(forResource: "phrases", withExtension: "json") {
            pathsToTry.append(bundleURL)
        }
        
        // 2) App Support: ~/Library/Application Support/FastSwitch/phrases.json
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent("FastSwitch", isDirectory: true)
            let userPhrases = appDir.appendingPathComponent("phrases.json")
            pathsToTry.append(userPhrases)
        }
        
        // 3) Executable directory (development run)
        let currentPath = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        pathsToTry.append(currentPath.appendingPathComponent("phrases.json"))
        
        for path in pathsToTry {
            if FileManager.default.fileExists(atPath: path.path) {
                do {
                    let data = try Data(contentsOf: path)
                    let phrasesData = try JSONDecoder().decode(PhrasesData.self, from: data)
                    logger.info("💡 Loaded phrases from: \(path.path)")
                    return phrasesData.phrases
                } catch {
                    logger.error("⚠️ Error loading phrases from \(path.path): \(error.localizedDescription)")
                }
            }
        }
        
        return nil
    }

    // Expose a safe reload entry for Preferences
    @objc func reloadMotivationalPhrases() {
        loadMotivationalPhrases()
    }
    
    private func loadDefaultPhrases() {
        // Default fallback phrases if external file not found
        motivationalPhrases = [
            MotivationalPhrase(
                id: "default_process_1",
                category: "proceso",
                text: "Concéntrate en el proceso no en el resultado",
                contexts: ["break", "stress", "work_session"],
                weight: 1.0
            ),
            MotivationalPhrase(
                id: "default_consistency_1",
                category: "proceso",
                text: "La consistencia vence al talento",
                contexts: ["morning", "work_session"],
                weight: 1.0
            ),
            MotivationalPhrase(
                id: "default_small_steps_1",
                category: "proceso",
                text: "Pequeños pasos, grandes logros",
                contexts: ["morning", "break", "reflection"],
                weight: 1.0
            ),
            MotivationalPhrase(
                id: "default_opportunity_1",
                category: "inicio",
                text: "Cada día es una nueva oportunidad",
                contexts: ["morning", "workday_start"],
                weight: 1.0
            ),
            MotivationalPhrase(
                id: "default_rest_work_1",
                category: "descanso",
                text: "El descanso es parte del trabajo",
                contexts: ["break", "tired"],
                weight: 1.0
            )
        ]
    }
    
    private func getMotivationalPhrase(for context: String) -> MotivationalPhrase? {
        // Filter phrases that match the context
        let contextPhrases = motivationalPhrases.filter { phrase in
            phrase.contexts.contains(context)
        }
        
        // Remove recently shown phrases to avoid repetition
        let availablePhrases = contextPhrases.filter { phrase in
            !recentPhrases.contains(phrase.id)
        }
        
        // If all phrases have been shown recently, reset the recent list
        let phrasesToUse = availablePhrases.isEmpty ? contextPhrases : availablePhrases
        
        // Select random phrase weighted by importance
        guard !phrasesToUse.isEmpty else { return nil }
        
        // For now, just pick randomly - could implement weighted selection
        let selectedPhrase = phrasesToUse.randomElement()
        
        // Track recently shown phrase
        if let phrase = selectedPhrase {
            recentPhrases.append(phrase.id)
            if recentPhrases.count > maxRecentPhrases {
                recentPhrases.removeFirst()
            }
        }
        
        return selectedPhrase
    }
    
    // MARK: - Wellness Notifications with Pavlovian Conditioning
    private func createWellnessNotification(
        type: WellnessNotificationType, 
        title: String, 
        body: String, 
        categoryIdentifier: String,
        actions: [UNNotificationAction] = []
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(type.icon) \(title)"
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(type.soundName))
        content.badge = NSNumber(value: 1)
        content.interruptionLevel = .active
        content.categoryIdentifier = categoryIdentifier
        
        // Add motivational phrase based on wellness type
        let context = getContextForWellnessType(type)
        self.addPhraseToNotification(content, context: context)
        
        // Set up category if actions provided
        if !actions.isEmpty {
            let category = UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
            UNUserNotificationCenter.current().setNotificationCategories([category])
        }
        
        return content
    }
    
    private func getContextForWellnessType(_ type: WellnessNotificationType) -> String {
        switch type {
        case .eyeBreak:      return "eye_care"
        case .posturalBreak: return "posture_care"
        case .hydration:     return "hydration"
        case .mate:          return "mate_reminder"
        case .exercise:      return "movement"
        case .deepBreath:    return "breathing"
        case .workBreak:     return "break"
        }
    }
    
    private func addPhraseToNotification(_ content: UNMutableNotificationContent, context: String) {
        if let phrase = getMotivationalPhrase(for: context) {
            // Add phrase to the notification body
            content.body += "\n\n💡 \"\(phrase.text)\""
            
            // Store phrase in today's reflection
            let todayKey = getTodayKey()
            if var todayData = usageHistory.dailyData[todayKey] {
                todayData.dailyReflection.phraseOfTheDay = phrase.text
                usageHistory.dailyData[todayKey] = todayData
                // Don't save immediately, will be saved when notification is handled
            }
        }
    }
    
    // MARK: - Specialized Wellness Notifications
    
    // (migrated) Wellness reminder scheduling handled by WellnessManager
    
    
    
    
    
    
    
    
    
    
    
    

    // MARK: - Quick Testing Mode (Debug Only)
    

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
                let cfg = NSWorkspace.OpenConfiguration()
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
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, _ in completion?() }
                return
            }
        }
        completion?()
    }
    
    

    // Detecta binarios en Apple Silicon/Intel
    private func bin(_ name: String) -> String {
        for p in ["/opt/homebrew/bin","/usr/local/bin","/usr/bin"] {
            let path = "\(p)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return name
    }
    
    
    
    @discardableResult
    private func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        try? p.run(); p.waitUntilExit(); return p.terminationStatus
    }
    
    
    @discardableResult
    private func sh(_ exe: String, _ args: [String] = []) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        try? p.run(); p.waitUntilExit(); return p.terminationStatus
    }
    
    
    // E-ink nítido (HiDPI). Probá 60 Hz primero; si notás glitches, cambiá a 40 Hz.
    private var eightHundredBySixHundred: String {
        return #"id:\#(DasungRefresher.shared.dasungDisplayUUID) res:800x600 hz:40 color_depth:8 scaling:on origin:(-800,0) degree:0"#
    }

    // Return to your current DASUNG mode
    private var nineHundredBySixHundredTwenty: String {
        return #"id:\#(DasungRefresher.shared.dasungDisplayUUID) res:960x720 hz:40 color_depth:8 scaling:on origin:(960,0) degree:0"#
    }

    
    //displayplacer "id:1E6E43E3-2C58-43E0-8813-B7079CD9FEFA res:800x600  hz:40  color_depth:8 scaling:on origin:(-800,0)  degree:0"
    
    //displayplacer "id:1E6E43E3-2C58-43E0-8813-B7079CD9FEFA res:960x720 hz:40 color_depth:8 scaling:on origin:(-960,0) degree:0"


    //displayplacer "id:1E6E43E3-2C58-43E0-8813-B7079CD9FEFA res:1100x826 hz:40 color_depth:8 scaling:on origin:(-1100,0) degree:0"
    

    //displayplacer "id:1E6E43E3-2C58-43E0-8813-B7079CD9FEFA res:1024x768 hz:40 color_depth:8 scaling:on origin:(-1024,0) degree:0"


    
    // Añade estas props (cerca de tus otras config vars)
    private var paperlikeEnabled = false
    private let paperlikeICCName = "Generic Gray Gamma 2.2" // cámbialo si elegiste otro
    private var grayscaleOn = false

    

    private func togglePaperlikeResolutionToggle() {
        paperlikeEnabled.toggle()
        let dp = "/opt/homebrew/bin/displayplacer"  // or /usr/local/bin for Intel
        _ = sh(dp, [paperlikeEnabled ? eightHundredBySixHundred : nineHundredBySixHundredTwenty])
        
        //if paperlikeEnabled {
        //    // Perfil de color en gris SOLO para el DASUNG
        //    _ = run(dprof, ["apply", paperlikeICCName])
        //}
        
        //if paperlikeEnabled {
        //    applyGrayICCtoDasung(iccName: "Generic Gray Gamma 2.2")
        //}
        logger.info("🖥️ Paperlike \(self.paperlikeEnabled ? "ON" : "OFF")")
    }
    
    private func toggleGlobalGrayscale() {
        grayscaleOn.toggle()
        let on = grayscaleOn ? "true" : "false"

        // habilitar/deshabilitar filtro
        _ = sh("/usr/bin/defaults", ["write","com.apple.universalaccess","colorFilterEnabled","-bool", on])

        if grayscaleOn {
            // 0 = Grayscale (otros tipos: 1 daltonismo/2…); intensidad 1.0
            _ = sh("/usr/bin/defaults", ["write","com.apple.universalaccess","colorFilterType","-int","0"])
            _ = sh("/usr/bin/defaults", ["write","com.apple.universalaccess","colorFilterIntensity","-float","1.0"])
        }

        // refrescar
        _ = sh("/usr/bin/killall", ["SystemUIServer"])
        logger.info("🎛️ Grayscale global \(self.grayscaleOn ? "ON" : "OFF")")
    }

    
    private func applyGrayICCtoDasung(iccName: String = "Generic Gray Gamma 2.2") {
        let script = #"""
        tell application "System Settings" to activate
        delay 0.5
        tell application "System Events"
          tell process "System Settings"
            -- Ir al panel Displays
            try
              click menu item "Displays" of menu "View" of menu bar 1
            end try
            delay 0.5
            -- Buscar el grupo del monitor DASUNG/Paperlike
            set targetGroup to missing value
            repeat with g in (groups of scroll area 1 of window 1)
              set desc to (value of attribute "AXDescription" of g) as text
              if desc contains "DASUNG" or desc contains "Paperlike" then
                set targetGroup to g
                exit repeat
              end if
            end repeat
            if targetGroup is missing value then return
            -- Abrir pop-up "Color profile" y elegir ICC
            click pop up button 1 of targetGroup
            delay 0.2
            click menu item iccName of menu 1 of pop up button 1 of targetGroup
          end tell
        end tell
        """#
        runAppleScript(script)
    }
    
    
    // MARK: - Spotify (bundle id)
    private func playPauseSpotifyWithRetry() {
        func tryPlay(_ remaining: Int) {
            if AppSwitchingManager.shared.isAppRunning(bundleID: "com.spotify.client") {
                runAppleScript(#"tell application "Spotify" to playpause"#)
            } else if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tryPlay(remaining - 1) }
            } else {
                logger.info("Spotify did not start in time; skipping play/pause")
            }
        }
        if !AppSwitchingManager.shared.isAppRunning(bundleID: "com.spotify.client") {
            AppSwitchingManager.shared.activateApp(bundleID: "com.spotify.client")
        }
        tryPlay(10)
    }

    // MARK: - Utilities
    

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
        runAppleScript(script, openPrefsOnError: false)
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
        runAppleScript(script, openPrefsOnError: false)
    }

    private func runAppleScript(_ script: String, openPrefsOnError: Bool = true) {
        var error: NSDictionary?
        if let s = NSAppleScript(source: script) {
            _ = s.executeAndReturnError(&error)
            if let error,
               let num = error[NSAppleScript.errorNumber] as? Int {
                if openPrefsOnError {
                    if num == 1002, // Accessibility not allowed
                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        AppSwitchingManager.shared.openURL(url)
                    } else if num == -1743, // Automation not permitted
                              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                        AppSwitchingManager.shared.openURL(url)
                    }
                }
                logger.error("AppleScript error: \(error[NSLocalizedDescriptionKey] as? String ?? String(describing: error))")
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
    
    // MARK: - Persistent Storage
    
    private func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func initializeTodayData() {
        let todayKey = getTodayKey()
        if usageHistory.dailyData[todayKey] == nil {
            usageHistory.dailyData[todayKey] = DailyUsageData(date: Date())
            logger.info("📅 Initializing data for today: \(todayKey)")
        }
    }
    
    private func saveTodayData() {
        let todayKey = getTodayKey()
        guard var todayData = usageHistory.dailyData[todayKey] else {
            logger.notice("⚠️ No data for today to save")
            return
        }
        
        // Update today's data with current session info
        todayData.totalSessionTime = UsageTrackingManager.shared.getCurrentSessionDuration()
        todayData.appUsage = UsageTrackingManager.shared.getAppUsageToday()
        todayData.breaksTaken = BreakReminderManager.shared.getBreaksTaken()
        todayData.continuousWorkSessions = UsageTrackingManager.shared.getContinuousWorkSessions()
        todayData.longestContinuousSession = UsageTrackingManager.shared.getLongestContinuousSession()
        todayData.totalBreakTime = BreakReminderManager.shared.getTotalBreakTime()
        todayData.callTime = UsageTrackingManager.shared.getCurrentDayCallTime()
        
        // Add current deep focus session if active
        if isDeepFocusEnabled, let startTime = deepFocusStartTime {
            let duration = Date().timeIntervalSince(startTime)
            todayData.deepFocusSessions.append(SessionRecord(start: startTime, duration: duration))
        }
        
        // Continuous sessions are now handled by UsageTrackingManager
        
        usageHistory.dailyData[todayKey] = todayData
        if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
        logger.info("💾 Saved today's data")
    }
    
    // MARK: - Usage Tracking
    
    
    
    private func checkUserActivity() {
        let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let keyboardIdleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        
        let minIdleTime = min(idleTime, keyboardIdleTime)
        let currentTime = Date()
        
        // App usage now tracked by UsageTrackingManager automatically
        
        // Check if user is in a call
        updateCallStatus()
        
        // Check for end of workday for daily reflection
        if detectEndOfWorkday() {
            WellnessManager.shared.askDailyReflection()
        }
        
        let effectiveIdleThreshold = isInCall ? callIdleThreshold : idleThreshold
        let sessionDuration = UsageTrackingManager.shared.getCurrentSessionDuration()
        
        logger.debug("🔍 Idle: \(Int(minIdleTime))s (mouse: \(Int(idleTime))s, keyboard: \(Int(keyboardIdleTime))s)")
        logger.debug("📞 In call: \(self.isInCall) (manual: \(self.manualCallToggle))")
        logger.debug("⏰ Session: \(Int(sessionDuration))s (\(Int(sessionDuration/60))min)")
        
        // Debug: Next notification countdown
        debugNextNotificationCountdown(sessionDuration: sessionDuration)
        
        if let frontApp = currentFrontApp {
            logger.debug("📱 Front app: \(frontApp)")
        }
        
        if minIdleTime < effectiveIdleThreshold {
            // User is active
            lastActivityTime = currentTime
            logger.debug("✅ Active (threshold: \(Int(effectiveIdleThreshold))s)")
            
            // Handle continuous session tracking
            if isCurrentlyOnBreak {
                // User was on break and is now active - end break
                BreakReminderManager.shared.endBreak()
            }
            
            if currentContinuousSessionStart == nil {
                // Start new continuous session
                startContinuousSession()
            }
            
            // Calculate session time and check for notifications
            if let startTime = sessionStartTime {
                let sessionDuration = currentTime.timeIntervalSince(startTime)
                BreakReminderManager.shared.checkForBreakNotification(sessionDuration: sessionDuration)
                updateStatusBarTitle(sessionDuration: sessionDuration)
            }
        } else {
            // User is idle - start break if not already on one
            logger.debug("😴 Inactive (threshold: \(Int(effectiveIdleThreshold))s)")
            
            if !isCurrentlyOnBreak {
                BreakReminderManager.shared.startBreak()
            }
            
            updateStatusBarTitle(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
        }
        
        // Periodic data saving (every minute when user is active)
        if Int(sessionDuration) % 60 == 0 && Int(sessionDuration) > 0 {
            saveTodayData()
        }
        
        // logger.debug("—")
    }
    
    private func debugNextNotificationCountdown(sessionDuration: TimeInterval) {
        guard notificationsEnabled else {
            logger.debug("🔕 Notifications disabled (debug)")
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
            
            logger.debug("🔔 Next notification #\(index + 1) in \(minutesLeft):\(String(format: "%02d", secondsLeft)) (interval: \(Int(next/60))min)")
            
            // Show progress bar in debug
            let progress = sessionDuration / next
            let progressBars = Int(progress * 20) // 20 character progress bar
            let progressString = String(repeating: "█", count: progressBars) + String(repeating: "░", count: 20 - progressBars)
            logger.debug("📊 Progress [\(progressString)] \(Int(progress * 100))%")
        } else {
            // Check if all notifications have been sent
            let allSent = notificationIntervals.allSatisfy { sentNotificationIntervals.contains($0) }
            if allSent {
                logger.debug("✅ All notifications sent for this session")
            } else {
                logger.debug("⚠️ No further notifications scheduled")
            }
        }
        
        // Debug break timer status
        if BreakReminderManager.shared.isBreakTimerActive, let startTime = breakTimerStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, 900 - elapsed) // Assuming 15min default
            let minutesLeft = Int(remaining / 60)
            let secondsLeft = Int(remaining.truncatingRemainder(dividingBy: 60))
            logger.debug("☕ Break timer active - Remaining \(minutesLeft):\(String(format: "%02d", secondsLeft))")
        }
        
        // Debug deep focus timer status
        if self.isDeepFocusEnabled, let startTime = self.deepFocusStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, self.customFocusDuration - elapsed)
            let minutesLeft = Int(remaining / 60)
            let secondsLeft = Int(remaining.truncatingRemainder(dividingBy: 60))
            logger.debug("🧘 Deep Focus active - Remaining \(minutesLeft):\(String(format: "%02d", secondsLeft)) (\(Int(self.customFocusDuration/60))min total)")
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
            if AppSwitchingManager.shared.isAppRunning(bundleID: bundleID) {
                detectedApps.append(bundleID)
                if bundleID == "com.google.Chrome" {
                    // Check if Chrome has a Meet tab
                    let hasMeet = chromeFrontTabIsMeet()
                    if hasMeet {
                        inCall = true
                        self.logger.debug("🌐 Chrome with Meet tab detected")
                    }
                } else {
                    inCall = true
                    logger.debug("📹 Call app detected: \(bundleID)")
                }
            }
        }
        
        if !detectedApps.isEmpty {
            logger.debug("📱 Call apps running: \(detectedApps)")
        }
        
        // Note: Microphone usage detection would require additional implementation on macOS
        // Could use AVCaptureDevice.authorizationStatus(for: .audio) if needed
        
        let wasInCall = self.isInCall
        self.isInCall = inCall
        
        if wasInCall != self.isInCall {
            logger.info("🔄 Call state changed: \(wasInCall) → \(self.isInCall)")
            
            // Track call time
            if self.isInCall {
                // Starting a call
                callStartTime = Date()
            } else if let startTime = callStartTime {
                // Ending a call
                let callDuration = Date().timeIntervalSince(startTime)
                currentDayCallTime += callDuration
                callStartTime = nil
                logger.info("📞 Call ended - Duration: \(Int(callDuration / 60))m")
            }
        }
    }
    
    
    // Break reminder scheduling handled by BreakReminderManager
    
    // Break reminder notifications handled by BreakReminderManager
    
    // Sticky break reminders handled by BreakReminderManager
    
    // MARK: - App Tracking
    private func getCurrentFrontApp() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return frontApp.bundleIdentifier ?? frontApp.localizedName ?? "Unknown"
    }
    
    
    // MARK: - Break and Session Tracking
    
    
    private func startContinuousSession() {
        guard currentContinuousSessionStart == nil else { return }
        
        currentContinuousSessionStart = Date()
        logger.info("🚀 Starting continuous session")
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
        let totalSession = UsageTrackingManager.shared.getCurrentSessionDuration()
        let sessionHours = Int(totalSession) / 3600
        let sessionMinutes = Int(totalSession) % 3600 / 60
        dashboard += "⏰ Total Work Session: \(sessionHours)h \(sessionMinutes)m\n\n"
        
        // App usage breakdown
        let appUsageToday = UsageTrackingManager.shared.getAppUsageToday()
        if !appUsageToday.isEmpty {
            dashboard += "📱 App Usage Breakdown:\n"
            
            // Calculate total usage time for percentage calculations
            let totalAppTime = appUsageToday.values.reduce(0, +)
            
            // Sort apps by usage time
            let sortedApps = appUsageToday.sorted { $0.value > $1.value }
            
            for (app, time) in sortedApps.prefix(10) { // Top 10 apps
                let hours = Int(time) / 3600
                let minutes = Int(time) % 3600 / 60
                let appName = AppSwitchingManager.shared.getAppDisplayName(from: app)
                
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
                let appName = AppSwitchingManager.shared.getAppDisplayName(from: app)
                
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
        let _ = yearData.reduce(0) { $0 + $1.totalBreakTime }
        let _ = yearData.reduce(0) { $0 + $1.callTime }
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
                let appName = AppSwitchingManager.shared.getAppDisplayName(from: app)
                
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
    
    
    private func askDailyReflection() {
        logger.info("📝 Asking for daily reflection")
        
        let content = UNMutableNotificationContent()
        content.title = "📝 Reflexión del Día"
        content.body = "¿Cómo fue tu día? Describe brevemente tu experiencia de trabajo y estado personal."
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "DAILY_REFLECTION"
        
        // Add motivational phrase
        self.addPhraseToNotification(content, context: "end_day")
        
        // Add reflection action buttons
        let writeJournalAction = UNNotificationAction(
            identifier: "WRITE_JOURNAL_ACTION",
            title: "✍️ Escribir Bitácora",
            options: [.foreground]
        )
        
        let quickMoodAction1 = UNNotificationAction(
            identifier: "MOOD_PRODUCTIVE",
            title: "💪 Productivo",
            options: []
        )
        
        let quickMoodAction2 = UNNotificationAction(
            identifier: "MOOD_BALANCED",
            title: "⚖️ Equilibrado",
            options: []
        )
        
        let quickMoodAction3 = UNNotificationAction(
            identifier: "MOOD_TIRED",
            title: "😴 Cansado",
            options: []
        )
        
        //let quickMoodAction4 = UNNotificationAction(
        //    identifier: "MOOD_STRESSED",
        //    title: "😤 Estresado",
        //    options: []
        //)
        
        let category = UNNotificationCategory(
            identifier: "DAILY_REFLECTION",
            actions: [writeJournalAction, quickMoodAction1, quickMoodAction2, quickMoodAction3],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "daily-reflection-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending daily reflection: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Daily reflection notification sent")
            }
        }
    }
    
    private func detectEndOfWorkday() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // End of workday detection: between 5PM-8PM and session has been running for 4+ hours
        guard hour >= 17 && hour <= 20 else { return false }
        
        let sessionDuration = now.timeIntervalSince(currentContinuousSessionStart ?? now)
        guard sessionDuration >= 14400 else { return false } // 4+ hours
        
        // Check if we haven't asked for reflection today
        let dateKey = getTodayKey()
        if let todayData = usageHistory.dailyData[dateKey] {
            return todayData.dailyReflection.completedAt == nil
        }
        return false
    }
    
    private func showDailyDashboard() {
        logger.info("📊 Showing daily dashboard")
        
        let content = UNMutableNotificationContent()
        content.title = "📊 Resumen del Día"
        content.body = generateDashboard()
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Submarine.aiff"))
        content.badge = NSNumber(value: 1)
        content.interruptionLevel = .active
        content.categoryIdentifier = "DAILY_DASHBOARD"
        
        // Add action buttons
        let weeklyReportAction = UNNotificationAction(
            identifier: "WEEKLY_REPORT_ACTION",
            title: "📈 Reporte Semanal",
            options: [.foreground]
        )
        
        let exportDataAction = UNNotificationAction(
            identifier: "EXPORT_DATA_ACTION",
            title: "💾 Exportar Datos",
            options: [.foreground]
        )
        
        let reflectionAction = UNNotificationAction(
            identifier: "START_REFLECTION_ACTION",
            title: "📝 Reflexionar",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "DAILY_DASHBOARD",
            actions: [reflectionAction, exportDataAction, weeklyReportAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "daily-dashboard-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending dashboard: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Daily dashboard sent")
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
        
        logger.info("📊 Dashboard scheduled for \(finalTargetTime)")
        
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
            let title = "F→ \(callIndicator)\(timeString)"
            MenuBarManager.shared.updateTitle(title)
            MenuBarManager.shared.updateSessionTime(duration: sessionDuration, isInCall: self.isInCall)
        }
    }
    
    private func updateMenuItems(sessionDuration: TimeInterval) {
        // Menu item updates now handled by MenuBarManager
        MenuBarManager.shared.updateCallStatus(manualCallToggle)
        MenuBarManager.shared.updateDeepFocusStatus(DeepFocusManager.shared.isEnabled)
    }
    
    @objc private func toggleCallStatus() {
        let newStatus = UsageTrackingManager.shared.toggleCallStatus()
        manualCallToggle = newStatus
        logger.info("🔄 Manual call toggle: \(newStatus)")
    }
    
    @objc private func toggleDeepFocusFromMenu() {
        DeepFocusManager.shared.toggleDeepFocus()
    }
    
    @objc private func openNotificationsPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Software sticky mode demo removed in favor of BreakReminderManager implementation
    
    @objc private func resetSession() {
        UsageTrackingManager.shared.resetSession()
        sentNotificationIntervals.removeAll()
        
        // Reset break and session tracking
        BreakReminderManager.shared.resetBreakTracking()
        
        logger.info("🔄 Session and break tracking reset")
    }
    
    @objc private func showDashboardManually() {
        logger.info("📊 Dashboard requested manually")
        showDailyDashboard()
    }
    
    @objc private func showWeeklyReport() {
        logger.info("📈 Weekly report requested")
        saveTodayData() // Ensure current data is saved
        showReport(title: "📈 Weekly Report", content: generateWeeklyReport(), identifier: "weekly-report")
    }
    
    @objc private func showYearlyReport() {
        logger.info("📅 Yearly report requested")
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
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending report: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Report sent: \(identifier)")
            }
        }
    }
    
    @objc private func exportUsageData() {
        logger.info("💾 Exporting usage data")
        // Save current day data
        if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
        
        if let exportURL = PersistenceManager.shared.exportUsageData() {
            // Show success notification
            NotificationManager.shared.scheduleSuccessNotification(
                title: "💾 Export Complete",
                message: "Usage data exported to Desktop:\n\(exportURL.lastPathComponent)\n\n📊 \(self.usageHistory.dailyData.count) days of data exported."
            )
            self.logger.info("✅ Exported usage data to: \(exportURL.path)")
        } else {
            // Show error notification
            NotificationManager.shared.scheduleErrorNotification(
                title: "❌ Export Failed",
                message: "Failed to export usage data to Desktop"
            )
        }
    }
    
    private func updateConfigurationMenuState() {
        // Configuration menu state now handled by MenuBarManager
        let mode: NotificationMode
        switch currentNotificationMode {
        case .testing:
            mode = .testing
        case .interval45:
            mode = .interval45
        case .interval60:
            mode = .interval60
        case .interval90:
            mode = .interval90
        case .disabled:
            mode = .disabled
        }
        MenuBarManager.shared.updateConfigurationMenu(mode: mode)
    }
    
    
    
    
    
    // MARK: - Configuration Methods
    @objc private func setNotificationIntervalTest() {
        notificationIntervals = [60, 300, 600] // 1min, 5min, 10min para testing
        notificationsEnabled = true
        currentNotificationMode = .testing
        sentNotificationIntervals.removeAll() // Reset sent notifications when changing intervals
        updateConfigurationMenuState()
        logger.info("🧪 Testing mode: 1-5-10 min intervals")
        logger.debug("🧪 Next notifications in: 1, 5, 10 minutes")
    }
    
    @objc private func setNotificationInterval45() {
        notificationIntervals = [2700, 5400, 8100] // 45min, 1.5hr, 2.25hr
        notificationsEnabled = true
        currentNotificationMode = .interval45
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        logger.info("⏰ Notification intervals set to 45min")
        logger.debug("⏰ Next: 45, 90, 135 minutes")
    }
    
    @objc private func setNotificationInterval60() {
        notificationIntervals = [3600, 7200, 10800] // 1hr, 2hr, 3hr
        notificationsEnabled = true
        currentNotificationMode = .interval60
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        logger.info("⏰ Notification intervals set to 60min")
        logger.debug("⏰ Next: 60, 120, 180 minutes")
    }
    
    @objc private func setNotificationInterval90() {
        notificationIntervals = [5400, 10800, 16200] // 1.5hr, 3hr, 4.5hr
        notificationsEnabled = true
        currentNotificationMode = .interval90
        sentNotificationIntervals.removeAll()
        updateConfigurationMenuState()
        logger.info("⏰ Notification intervals set to 90min")
        logger.debug("⏰ Next: 90, 180, 270 minutes")
    }
    
    @objc private func disableNotifications() {
        notificationsEnabled = false
        currentNotificationMode = .disabled
        updateConfigurationMenuState()
        logger.info("🔕 Notifications disabled")
        logger.debug("🔕 No reminders will be sent")
    }
    
    // MARK: - NotificationManagerDelegate
    func notificationManager(_ manager: NotificationManager, shouldPresentNotification notification: UNNotification) -> UNNotificationPresentationOptions {
        // Show notification even when app is active
        return [.banner, .sound, .badge]
    }
    
    func notificationManager(_ manager: NotificationManager, didReceiveAction actionId: String, with response: UNNotificationResponse) {
        switch response.actionIdentifier {
        case "DISMISS_ACTION":
            logger.info("✅ User confirmed break notification")
            // Stop sticky break notifications
            BreakReminderManager.shared.stopStickyBreakReminders()
            // Clear badge
            NSApp.dockTile.badgeLabel = nil
            
        case "SNOOZE_ACTION":
            logger.info("⏰ User snoozed notification for 5 minutes")
            // Stop sticky break notifications
            BreakReminderManager.shared.stopStickyBreakReminders()
            // Schedule a snooze notification in 5 minutes
            scheduleSnoozeNotification()
            
        case "CONTINUE_FOCUS_ACTION":
            logger.info("🧘 User chose to continue Deep Focus")
            // Stop sticky notifications since user clicked
            self.stopStickyDeepFocusNotification()
            // Delegate focus handling to DeepFocusManager
            DeepFocusManager.shared.start60MinuteSession()
            NSApp.dockTile.badgeLabel = nil
            
        case "TAKE_BREAK_ACTION":
            logger.info("☕ User chose to take a break")
            // Stop sticky notifications since user clicked
            self.stopStickyDeepFocusNotification()
            // Disable Deep Focus
            if DeepFocusManager.shared.isEnabled {
                DeepFocusManager.shared.disableFocus()
            }
            NSApp.dockTile.badgeLabel = nil
            
        case "DISMISS_FOCUS_ACTION":
            logger.info("✅ User confirmed Deep Focus notification")
            // Stop sticky notifications since user clicked
            self.stopStickyDeepFocusNotification()
            NSApp.dockTile.badgeLabel = nil
            
        case "DASHBOARD_OK_ACTION":
            logger.info("📊 User acknowledged daily dashboard")
            NSApp.dockTile.badgeLabel = nil
            
        case "DASHBOARD_RESET_ACTION":
            logger.info("🔄 User requested reset from dashboard")
            resetSession()
            NSApp.dockTile.badgeLabel = nil
            
        case "REPORT_OK_ACTION":
            logger.info("📊 User confirmed report")
            NSApp.dockTile.badgeLabel = nil
            
        // New Break Reminder Actions
        case "START_BREAK_ACTION":
            logger.info("☕ User started break from notification")
            BreakReminderManager.shared.startBreakTimer(duration: 900) // 15 minutes
            BreakReminderManager.shared.stopStickyBreakReminders()
            NSApp.dockTile.badgeLabel = nil
            
        case "KEEP_WORKING_ACTION":
            logger.info("🏃 User chose to keep working")
            // Reset session start time to extend current session
            sessionStartTime = Date()
            sentNotificationIntervals.removeAll()
            BreakReminderManager.shared.stopStickyBreakReminders()
            NSApp.dockTile.badgeLabel = nil
            
        case "SHOW_STATS_ACTION":
            logger.info("📊 User requested stats from notification")
            showDailyDashboard()
            BreakReminderManager.shared.stopStickyBreakReminders()
            NSApp.dockTile.badgeLabel = nil
            
        // New Deep Focus Actions
        case "FOCUS_ANOTHER_HOUR_ACTION":
            logger.info("🧘 User chose to focus another hour")
            self.stopStickyDeepFocusNotification()
            // Delegate to DeepFocusManager 60-minute session
            DeepFocusManager.shared.start60MinuteSession()
            NSApp.dockTile.badgeLabel = nil
            
        case "TAKE_15MIN_BREAK_ACTION":
            logger.info("☕ User chose 15-min break")
            self.stopStickyDeepFocusNotification()
            if DeepFocusManager.shared.isEnabled { DeepFocusManager.shared.disableFocus() }
            BreakReminderManager.shared.startBreakTimer(duration: 900) // 15 minutes
            NSApp.dockTile.badgeLabel = nil
            
        case "SHOW_SESSION_STATS_ACTION":
            logger.info("📊 User requested session stats")
            self.stopStickyDeepFocusNotification()
            showDailyDashboard()
            NSApp.dockTile.badgeLabel = nil
            
        case "SET_CUSTOM_FOCUS_ACTION":
            logger.info("🎯 User chose custom focus duration")
            self.stopStickyDeepFocusNotification()
            self.showCustomFocusDurationOptions()
            NSApp.dockTile.badgeLabel = nil
            
        // Break Timer Complete Actions
        case "BACK_TO_WORK_ACTION":
            logger.info("🏃 Back to work")
            BreakReminderManager.shared.stopBreakTimer()
            NSApp.dockTile.badgeLabel = nil
            
        case "EXTEND_BREAK_ACTION":
            logger.info("☕ User extended break 5min")
            BreakReminderManager.shared.startBreakTimer(duration: 300) // 5 more minutes
            NSApp.dockTile.badgeLabel = nil
            
        case "SHOW_DASHBOARD_ACTION":
            logger.info("📊 User requested dashboard from break timer")
            showDailyDashboard()
            NSApp.dockTile.badgeLabel = nil
            
        // New Dashboard Actions
        case "WEEKLY_REPORT_ACTION":
            logger.info("📈 User requested weekly report from dashboard")
            showWeeklyReport()
            NSApp.dockTile.badgeLabel = nil
            
        case "EXPORT_DATA_ACTION":
            logger.info("💾 User requested export from dashboard")
            exportUsageData()
            NSApp.dockTile.badgeLabel = nil
            
        case "SET_GOAL_ACTION":
            logger.info("🎯 User wants to set a goal")
            // For now, just show a confirmation
            // In a full implementation, this could show a goal-setting interface
            NSApp.dockTile.badgeLabel = nil
            
        // Daily Reflection Actions
        case "WRITE_JOURNAL_ACTION":
            logger.info("✍️ User chose to write full journal entry")
            openJournalInterface()
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_PRODUCTIVE":
            logger.info("💪 Mood: productive")
            _ = WellnessManager.shared.saveDailyReflection(mood: "productive", notes: "Día productivo")
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_BALANCED":
            logger.info("⚖️ Mood: balanced")
            _ = WellnessManager.shared.saveDailyReflection(mood: "balanced", notes: "Día equilibrado")
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_TIRED":
            logger.info("😴 Mood: tired")
            _ = WellnessManager.shared.saveDailyReflection(mood: "tired", notes: "Día cansado")
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_STRESSED":
            logger.info("😤 Mood: stressed")
            _ = WellnessManager.shared.saveDailyReflection(mood: "stressed", notes: "Día estresado")
            NSApp.dockTile.badgeLabel = nil
            
        case "START_REFLECTION_ACTION":
            logger.info("📝 User started reflection from dashboard")
            WellnessManager.shared.askDailyReflection()
            NSApp.dockTile.badgeLabel = nil
            
        // Wellness Question Actions - Mate and Sugar
        case "MATE_NONE":
            logger.info("🧉 Mate: 0 termos")
            WellnessManager.shared.recordMate(thermosCount: 0)
            NSApp.dockTile.badgeLabel = nil
            
        case "MATE_LOW":
            logger.info("🧉 Mate: 1 termo")
            WellnessManager.shared.recordMate(thermosCount: 1)
            NSApp.dockTile.badgeLabel = nil
            
        case "MATE_MEDIUM":
            logger.info("🧉 Mate: 2 termos")
            WellnessManager.shared.recordMate(thermosCount: 2)
            NSApp.dockTile.badgeLabel = nil
            
        case "MATE_HIGH":
            logger.info("🧉 Mate: 3+ termos")
            WellnessManager.shared.recordMate(thermosCount: 3)
            NSApp.dockTile.badgeLabel = nil
            
        // New Mate Reminder Actions
        case "RECORD_MATE_ACTION":
            logger.info("✅ Mate recorded from reminder")
            WellnessManager.shared.recordMate(thermosCount: 1)
            NSApp.dockTile.badgeLabel = nil
            
        case "SKIP_MATE_ACTION":
            logger.info("⏭️ Mate skipped from reminder")
            NSApp.dockTile.badgeLabel = nil
            
        // Wellness Question Actions - Exercise
        case "EXERCISE_NO":
            logger.info("🏃 Exercise: none")
            WellnessManager.shared.recordExercise(type: "none", duration: 0, intensity: "none")
            NSApp.dockTile.badgeLabel = nil
            
        case "EXERCISE_LIGHT":
            logger.info("🏃 Exercise: light 15min")
            WellnessManager.shared.recordExercise(type: "walk", duration: 15, intensity: "light")
            NSApp.dockTile.badgeLabel = nil
            
        case "EXERCISE_MODERATE":
            logger.info("🏃 Exercise: moderate 30min")
            WellnessManager.shared.recordExercise(type: "moderate", duration: 30, intensity: "moderate")
            NSApp.dockTile.badgeLabel = nil
            
        case "EXERCISE_INTENSE":
            logger.info("🏃 Exercise: intense 45min+")
            WellnessManager.shared.recordExercise(type: "intense", duration: 45, intensity: "intense")
            NSApp.dockTile.badgeLabel = nil
            
        // Wellness Question Actions - Energy
        case "ENERGY_LOW":
            logger.info("⚡ Energy: low")
            WellnessManager.shared.recordWellnessCheck(type: "energy", level: 2, context: "work_session")
            NSApp.dockTile.badgeLabel = nil
            
        case "ENERGY_MEDIUM":
            logger.info("⚡ Energy: medium")
            WellnessManager.shared.recordWellnessCheck(type: "energy", level: 5, context: "work_session")
            NSApp.dockTile.badgeLabel = nil
            
        case "ENERGY_HIGH":
            logger.info("⚡ Energy: high")
            WellnessManager.shared.recordWellnessCheck(type: "energy", level: 8, context: "work_session")
            NSApp.dockTile.badgeLabel = nil
            
        // New Wellness Actions
        case "EYE_BREAK_DONE":
            logger.info("👁️ Eye break done")
            WellnessManager.shared.recordWellnessCheck(type: "eye_break", level: 1, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case "EYE_BREAK_SKIP":
            logger.info("👁️ Eye break skipped")
            WellnessManager.shared.recordWellnessCheck(type: "eye_break", level: 0, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case "POSTURE_BREAK_DONE":
            logger.info("🧘‍♂️ Posture break done")
            WellnessManager.shared.recordWellnessCheck(type: "posture_break", level: 1, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case "POSTURE_BREAK_SKIP":
            logger.info("🧘‍♂️ Posture break skipped")
            WellnessManager.shared.recordWellnessCheck(type: "posture_break", level: 0, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case "HYDRATION_DONE":
            logger.info("💧 Hydration done")
            WellnessManager.shared.recordWellnessCheck(type: "hydration", level: 1, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case "HYDRATION_SKIP":
            logger.info("💧 Hydration skipped")
            WellnessManager.shared.recordWellnessCheck(type: "hydration", level: 0, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case "BREATHING_DONE":
            logger.info("🫁 Breathing done")
            WellnessManager.shared.recordWellnessCheck(type: "breathing", level: 1, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case "BREATHING_SKIP":
            logger.info("🫁 Breathing skipped")
            WellnessManager.shared.recordWellnessCheck(type: "breathing", level: 0, context: "break")
            NSApp.dockTile.badgeLabel = nil
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            logger.info("👆 User tapped notification")
            // Stop sticky notifications based on notification type
            let categoryIdentifier = response.notification.request.content.categoryIdentifier
            if categoryIdentifier == "DEEP_FOCUS_COMPLETE" {
                self.stopStickyDeepFocusNotification()
            } else if categoryIdentifier == "BREAK_REMINDER" {
                BreakReminderManager.shared.stopStickyBreakReminders()
            }
            NSApp.dockTile.badgeLabel = nil
            
        default:
            break
        }
    }
    
    // MARK: - Daily Reflection and Journal Functions
    private func saveDailyReflection(mood: String, notes: String) {
        let dateKey = getTodayKey()
        
        // Get or create today's data
        var todayData = usageHistory.dailyData[dateKey] ?? DailyUsageData(date: Date())
        
        // Create reflection record
        var reflection = DailyReflection()
        reflection.dayType = mood
        reflection.journalEntry = notes
        reflection.completedAt = Date()
        
        // Save reflection
        todayData.dailyReflection = reflection
        usageHistory.dailyData[dateKey] = todayData
        if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
        
        logger.info("✅ Daily reflection saved - Mood: \(mood)")
        
        // Show confirmation
        let content = UNMutableNotificationContent()
        content.title = "✅ Reflexión Guardada"
        content.body = "Tu reflexión diaria ha sido registrada. ¡Gracias por compartir cómo te sentiste hoy!"
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(
            identifier: "reflection-saved-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func openJournalInterface() {
        logger.info("✍️ Opening journal interface")
        
        // Create an Apple Script to show a text input dialog
        let script = """
        tell application "System Events"
            activate
            set userResponse to display dialog "Escribe tu reflexión del día:" & return & return & "¿Cómo te sentiste? ¿Qué lograste? ¿Qué mejorarías?" with title "📝 Bitácora Personal" default answer "" giving up after 120 buttons {"Cancelar", "Guardar"} default button "Guardar"
            
            if button returned of userResponse is "Guardar" then
                set journalText to text returned of userResponse
                return journalText
            else
                return "CANCELLED"
            end if
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        
        if let result = appleScript?.executeAndReturnError(&error) {
            let journalText = result.stringValue ?? ""
            
            if journalText != "CANCELLED" && !journalText.isEmpty {
                // Save the journal entry with mood detection
                let mood = detectMoodFromText(journalText)
                _ = WellnessManager.shared.saveDailyReflection(mood: mood, notes: journalText)
            } else {
                self.logger.info("📝 User cancelled or wrote nothing")
            }
        } else if let error = error {
            logger.error("❌ Journal script error: \(error[NSLocalizedDescriptionKey] as? String ?? String(describing: error))")
            
            // Fallback: simple notification asking for quick mood
            askQuickMoodOnly()
        }
    }
    
    private func detectMoodFromText(_ text: String) -> String {
        let lowercaseText = text.lowercased()
        
        // Stress indicators
        if lowercaseText.contains("estresad") || lowercaseText.contains("agobiad") || 
           lowercaseText.contains("ansiedad") || lowercaseText.contains("presión") ||
           lowercaseText.contains("sobrecarga") || lowercaseText.contains("tensión") {
            return "stressed"
        }
        
        // Tired indicators
        if lowercaseText.contains("cansad") || lowercaseText.contains("agotad") ||
           lowercaseText.contains("fatiga") || lowercaseText.contains("sueño") ||
           lowercaseText.contains("rendid") || lowercaseText.contains("sin energía") {
            return "tired"
        }
        
        // Productive indicators
        if lowercaseText.contains("productiv") || lowercaseText.contains("logr") ||
           lowercaseText.contains("complet") || lowercaseText.contains("eficient") ||
           lowercaseText.contains("éxito") || lowercaseText.contains("avance") ||
           lowercaseText.contains("cumpl") {
            return "productive"
        }
        
        // Default to balanced if no clear indicators
        return "balanced"
    }
    
    private func askQuickMoodOnly() {
        let content = UNMutableNotificationContent()
        content.title = "📝 Reflexión Rápida"
        content.body = "¿Cómo te sentiste hoy en general?"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "QUICK_MOOD"
        
        let productiveAction = UNNotificationAction(
            identifier: "MOOD_PRODUCTIVE",
            title: "💪 Productivo",
            options: []
        )
        
        let balancedAction = UNNotificationAction(
            identifier: "MOOD_BALANCED", 
            title: "⚖️ Equilibrado",
            options: []
        )
        
        let tiredAction = UNNotificationAction(
            identifier: "MOOD_TIRED",
            title: "😴 Cansado", 
            options: []
        )
        
        let stressedAction = UNNotificationAction(
            identifier: "MOOD_STRESSED",
            title: "😤 Estresado",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "QUICK_MOOD",
            actions: [productiveAction, balancedAction, tiredAction, stressedAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "quick-mood-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func scheduleSnoozeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Snooze Reminder"
        content.body = "🔔 This is your 5-minute break reminder.\n\n🚶‍♂️ Don't forget to take that break!\n\n👆 Click to dismiss."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Ping.aiff"))
        content.badge = NSNumber(value: 1)
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
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error scheduling snooze: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Snooze scheduled for 5 minutes")
            }
        }
    }
    
    // MARK: - Mate Reduction Plan Functions
    @objc private func showMateProgress() {
        // Read current plan from WellnessManager and today's total from persisted data
        let plan = WellnessManager.shared.getMateReductionPlan()
        let target = plan.getCurrentTargetThermos()
        let schedule = plan.getCurrentSchedule().joined(separator: " • ")
        let phase = plan.currentPhase + 1
        
        let todayKey = getTodayKey()
        let todayTotal = usageHistory.dailyData[todayKey]?.wellnessMetrics.mateRecords.reduce(0) { $0 + $1.thermosCount } ?? 0
        
        let content = UNMutableNotificationContent()
        content.title = "🧉 Estado del Plan de Mate"
        content.body = """
        Fase \(phase)/4: \(target) termos por día
        Total hoy: \(todayTotal)/\(target)
        
        Horarios: \(schedule)
        """
        content.sound = UNNotificationSound.default
        
        self.addPhraseToNotification(content, context: "mate_progress")
        
        let request = UNNotificationRequest(
            identifier: "mate-progress-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func updateMateMenuStatus() {
        // Mate status now handled by MenuBarManager; compute totals from persisted data
        let plan = WellnessManager.shared.getMateReductionPlan()
        let target = plan.getCurrentTargetThermos()
        let phase = plan.currentPhase + 1
        let todayKey = getTodayKey()
        let todayTotal = usageHistory.dailyData[todayKey]?.wellnessMetrics.mateRecords.reduce(0) { $0 + $1.thermosCount } ?? 0
        MenuBarManager.shared.updateMateStatus(phase: phase, current: todayTotal, target: target)
    }
    
    
    
    
    // MARK: - DASUNG menú
    private var dasungItem: NSStatusItem?

    @objc private func actRefresh() { DasungRefresher.shared.refreshPaperlike() }

    @objc private func actM1() { _ = DasungDDC.shared.setDithering(.M1) }
    @objc private func actM2() { _ = DasungDDC.shared.setDithering(.M2) }
    @objc private func actM3() { _ = DasungDDC.shared.setDithering(.M3) }
    @objc private func actM4() { _ = DasungDDC.shared.setDithering(.M4) }

    @objc private func actFastPP() { _ = DasungDDC.shared.setRefresh(.fastPP) }
    @objc private func actFastP()  { _ = DasungDDC.shared.setRefresh(.fastP) }
    @objc private func actFast()   { _ = DasungDDC.shared.setRefresh(.fast) }
    @objc private func actBlackP() { _ = DasungDDC.shared.setRefresh(.blackP) }   // “Tinta+”
    @objc private func actBlackPP(){ _ = DasungDDC.shared.setRefresh(.blackPP) }  // “Tinta++”

    private func setupDasungMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🖤"
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Refrescar DASUNG", action: #selector(actRefresh), keyEquivalent: ""))

        menu.addItem(.separator())

        let dith = NSMenu(title: "Modo (M1–M4)")
        dith.addItem(NSMenuItem(title: "M1", action: #selector(actM1), keyEquivalent: ""))
        dith.addItem(NSMenuItem(title: "M2", action: #selector(actM2), keyEquivalent: ""))
        dith.addItem(NSMenuItem(title: "M3", action: #selector(actM3), keyEquivalent: ""))
        dith.addItem(NSMenuItem(title: "M4", action: #selector(actM4), keyEquivalent: ""))
        let dithItem = NSMenuItem(title: "Modo (M1–M4)", action: nil, keyEquivalent: "")
        dithItem.submenu = dith
        menu.addItem(dithItem)

        let spd = NSMenu(title: "Velocidad / Tinta")
        spd.addItem(NSMenuItem(title: "Rápido++", action: #selector(actFastPP), keyEquivalent: ""))
        spd.addItem(NSMenuItem(title: "Rápido+",  action: #selector(actFastP),  keyEquivalent: ""))
        spd.addItem(NSMenuItem(title: "Rápido",   action: #selector(actFast),   keyEquivalent: ""))
        spd.addItem(NSMenuItem(title: "Tinta+",   action: #selector(actBlackP), keyEquivalent: ""))
        spd.addItem(NSMenuItem(title: "Tinta++",  action: #selector(actBlackPP),keyEquivalent: ""))
        let spdItem = NSMenuItem(title: "Velocidad / Tinta", action: nil, keyEquivalent: "")
        spdItem.submenu = spd
        menu.addItem(spdItem)

        item.menu = menu
        self.dasungItem = item
    }
    
    
    
}




// ==============================================================
// INTEGRACIÓN con tu AppDelegate existente
// --------------------------------------------------------------
// 1) Conservá tus structs/phrase system. Este manager puede reutilizar
//    `motivationalPhrases.map { $0.text }` de tu app.
// 2) Agregá estas propiedades y acciones al AppDelegate.
extension AppDelegate {

    @objc func togglePhraseWallpaper() {
        if WallpaperPhraseManager.shared.isEnabled {
            WallpaperPhraseManager.shared.stop()
            AppConfig.wallpaperEnabled = false
        } else {
            let fallback = ["Concéntrate en el proceso, no en el resultado",
                            "La consistencia vence al talento",
                            "Pequeños pasos, grandes logros",
                            "Cada día es una nueva oportunidad",
                            "El descanso es parte del trabajo"]
            let list = motivationalPhrases.isEmpty ? fallback : motivationalPhrases.map { $0.text }
            WallpaperPhraseManager.shared.start(phrases: list, interval: WallpaperPhraseManager.shared.interval)
            AppConfig.wallpaperEnabled = true
        }
        updateWallpaperMenuState()
    }

    @objc func changePhraseNow() { WallpaperPhraseManager.shared.updateNow() }
    @objc func setWPInterval15() { WallpaperPhraseManager.shared.interval = 15*60; WallpaperPhraseManager.shared.updateNow(); updateWallpaperMenuState() }
    @objc func setWPInterval30() { WallpaperPhraseManager.shared.interval = 30*60; WallpaperPhraseManager.shared.updateNow(); updateWallpaperMenuState() }
    @objc func setWPInterval60() { WallpaperPhraseManager.shared.interval = 60*60; WallpaperPhraseManager.shared.updateNow(); updateWallpaperMenuState() }


    // Single refresh function (no parameter)
    func updateWallpaperMenuState() {
        // Wallpaper menu state now handled by MenuBarManager
        let intervalMinutes = Int(WallpaperPhraseManager.shared.interval / 60)
        MenuBarManager.shared.updateWallpaperMenu(
            isEnabled: WallpaperPhraseManager.shared.isEnabled,
            intervalMinutes: intervalMinutes
        )
    }
}

// MARK: - PersistenceManagerDelegate

extension AppDelegate {
    func persistenceManager(_ manager: PersistenceManager, didLoadUsageHistory history: UsageHistory) {
        usageHistory = history
        logger.info("📂 Usage history loaded via PersistenceManager")
    }
    
    func persistenceManager(_ manager: PersistenceManager, didFailWithError error: Error) {
        logger.error("❌ PersistenceManager error: \(error.localizedDescription)")
        
        // Show error notification
        NotificationManager.shared.scheduleErrorNotification(
            title: "💾 Data Error",
            message: "Failed to save/load data: \(error.localizedDescription)"
        )
    }
}

// MARK: - UsageTrackingManagerDelegate

extension AppDelegate {
    func usageTrackingManager(_ manager: UsageTrackingManager, didUpdateSessionDuration duration: TimeInterval) {
        // Update status bar with current session duration
        updateStatusBarTitle(sessionDuration: duration)
    }
    
    func usageTrackingManager(_ manager: UsageTrackingManager, didDetectActivity isActive: Bool) {
        // Handle activity detection for break management
        if !isActive && !isCurrentlyOnBreak {
            BreakReminderManager.shared.startBreak()
        }
    }
    
    func usageTrackingManager(_ manager: UsageTrackingManager, didUpdateAppUsage appUsage: [String: TimeInterval]) {
        // App usage tracking updated - no immediate action needed
        // Data will be retrieved when saving today's data
    }
    
    func usageTrackingManager(_ manager: UsageTrackingManager, didDetectCallStatus inCall: Bool) {
        // Update UI state for call detection
        manualCallToggle = inCall
        
        // Update menu items to reflect call status
        updateMenuItems(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
        
        logger.info("📞 Call status changed: \(inCall)")
    }
}

// MARK: - BreakReminderManagerDelegate

extension AppDelegate {
    func breakReminderManager(_ manager: BreakReminderManager, didStartBreak duration: TimeInterval) {
        // Update UI to reflect break state
        updateMenuItems(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
        logger.info("☕ Break started via BreakReminderManager")
    }
    
    func breakReminderManager(_ manager: BreakReminderManager, didEndBreak duration: TimeInterval) {
        // Update UI to reflect work state
        updateMenuItems(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
        
        let minutes = Int(duration / 60)
        logger.info("🔄 Break ended after \(minutes) minutes via BreakReminderManager")
    }
    
    func breakReminderManager(_ manager: BreakReminderManager, didSendBreakNotification sessionDuration: TimeInterval) {
        // Log break notification sent
        let minutes = Int(sessionDuration / 60)
        logger.info("📢 Break notification sent for \(minutes) minute session")
    }
    
    func breakReminderManager(_ manager: BreakReminderManager, needsNotification request: UNNotificationRequest) {
        // Send notification via system
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending break notification: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Break notification sent successfully")
            }
        }
    }
}

// MARK: - WellnessManagerDelegate

extension AppDelegate {
    func wellnessManager(_ manager: WellnessManager, needsNotification request: UNNotificationRequest) {
        // Send wellness notification via system
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending wellness notification: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Wellness notification sent successfully")
            }
        }
    }
    
    func wellnessManager(_ manager: WellnessManager, didUpdateMateProgress thermos: Int, target: Int) {
        // Persist mate record and update menu status
        let todayKey = getTodayKey()
        var todayData = usageHistory.dailyData[todayKey] ?? DailyUsageData(date: Date())
        let record = MateRecord(time: Date(), thermosCount: thermos, type: "mate")
        todayData.wellnessMetrics.mateRecords.append(record)
        usageHistory.dailyData[todayKey] = todayData
        if let saved = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(saved)
        }
        updateMateMenuStatus()
        logger.info("🧉 Mate progress saved: +\(thermos) (target: \(target))")
    }
    
    func wellnessManager(_ manager: WellnessManager, didAdvancePhase newPhase: Int) {
        // Update UI for phase advancement
        logger.info("📈 Mate reduction advanced to phase \(newPhase)")
    }
    
    func wellnessManager(_ manager: WellnessManager, didSaveDailyReflection reflection: DailyReflection) {
        // Save reflection to today's data
        let todayKey = getTodayKey()
        guard var todayData = usageHistory.dailyData[todayKey] else { return }
        
        todayData.dailyReflection = reflection
        usageHistory.dailyData[todayKey] = todayData
        PersistenceManager.shared.saveDailyData(todayData)
        
        logger.info("📝 Daily reflection saved via WellnessManager")
    }

    func wellnessManager(_ manager: WellnessManager, didRecordExercise record: ExerciseRecord) {
        let todayKey = getTodayKey()
        var todayData = usageHistory.dailyData[todayKey] ?? DailyUsageData(date: Date())
        todayData.wellnessMetrics.exerciseRecords.append(record)
        usageHistory.dailyData[todayKey] = todayData
        if let saved = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(saved)
        }
        logger.info("🏃 Exercise saved: type=\(record.type), duration=\(record.duration)m")
    }

    func wellnessManager(_ manager: WellnessManager, didRecordWellnessCheck check: WellnessCheck) {
        let todayKey = getTodayKey()
        var todayData = usageHistory.dailyData[todayKey] ?? DailyUsageData(date: Date())
        switch check.type.lowercased() {
        case "energy":
            todayData.wellnessMetrics.energyLevels.append(check)
        case "stress":
            todayData.wellnessMetrics.stressLevels.append(check)
        default:
            todayData.wellnessMetrics.moodChecks.append(check)
        }
        usageHistory.dailyData[todayKey] = todayData
        if let saved = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(saved)
        }
        logger.info("🌱 Wellness check saved: type=\(check.type), level=\(check.level)")
    }
}

// MARK: - MenuBarManagerDelegate

extension AppDelegate {
    func menuBarManager(_ manager: MenuBarManager, requestAutomationPermissions: Void) {
        requestAutomationPrompts()
    }
    
    func menuBarManager(_ manager: MenuBarManager, toggleCallStatus: Void) {
        _ = UsageTrackingManager.shared.toggleCallStatus()
    }
    
    func menuBarManager(_ manager: MenuBarManager, toggleDeepFocus: Void) {
        DeepFocusManager.shared.toggleDeepFocus()
    }
    
    func menuBarManager(_ manager: MenuBarManager, resetSession: Void) {
        UsageTrackingManager.shared.resetSession()
    }
    
    func menuBarManager(_ manager: MenuBarManager, showDashboard: Void) {
        showDashboardManually()
    }
    
    func menuBarManager(_ manager: MenuBarManager, showWeeklyReport: Void) {
        logger.info("📊 Weekly report requested (not implemented)")
    }

    func menuBarManager(_ manager: MenuBarManager, showYearlyReport: Void) {
        logger.info("📊 Yearly report requested (not implemented)")
    }
    
    func menuBarManager(_ manager: MenuBarManager, exportData: Void) {
        exportUsageData()
    }
    
    func menuBarManager(_ manager: MenuBarManager, showMateProgress: Void) {
        self.showMateProgress()
    }
    
    func menuBarManager(_ manager: MenuBarManager, setNotificationMode mode: NotificationMode) {
        switch mode {
        case .testing:
            setNotificationIntervalTest()
        case .interval45:
            setNotificationInterval45()
        case .interval60:
            setNotificationInterval60()
        case .interval90:
            setNotificationInterval90()
        case .disabled:
            disableNotifications()
        }
    }
    
    func menuBarManager(_ manager: MenuBarManager, openNotificationPrefs: Void) {
        openNotificationsPrefs()
    }
    
    func menuBarManager(_ manager: MenuBarManager, quitApp: Void) {
        quit()
    }
    
    func menuBarManager(_ manager: MenuBarManager, toggleWallpaperPhrases: Void) {
        togglePhraseWallpaper()
    }
    
    func menuBarManager(_ manager: MenuBarManager, changeWallpaperNow: Void) {
        changePhraseNow()
    }
    
    func menuBarManager(_ manager: MenuBarManager, setWallpaperInterval minutes: Int) {
        switch minutes {
        case 15:
            setWPInterval15()
        case 30:
            setWPInterval30()
        case 60:
            setWPInterval60()
        default:
            break
        }
    }
}

// MARK: - DeepFocusManagerDelegate

extension AppDelegate {
    func deepFocusManager(_ manager: DeepFocusManager, didToggleFocus enabled: Bool) {
        // Update menu bar focus status
        MenuBarManager.shared.updateDeepFocusStatus(enabled)
        updateStatusBarForFocus()
    }
    
    func deepFocusManager(_ manager: DeepFocusManager, needsSlackDND enabled: Bool) {
        if enabled {
            enableSlackDND()
        } else {
            disableSlackDND()
        }
    }
    
    func deepFocusManager(_ manager: DeepFocusManager, needsSystemDND enabled: Bool) {
        if enabled {
            enableSystemDND()
        } else {
            disableSystemDND()
        }
    }
    
    func deepFocusManager(_ manager: DeepFocusManager, needsNotification request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ Error sending Deep Focus notification: \(error.localizedDescription)")
            } else {
                self?.logger.info("✅ Deep Focus sticky notification sent")
            }
        }
    }
    
    func deepFocusManager(_ manager: DeepFocusManager, didCompleteSession duration: TimeInterval) {
        // Record the focus session
        let minutes = Int(duration / 60)
        logger.info("🧘 Deep Focus session completed (\(minutes)min)")
        
        // Could save to persistence or analytics here
        saveTodayData()
    }

    // MARK: - Missing DND Helper Functions

    private func enableSystemDND() {
        // Enable system Do Not Disturb via AppleScript
        let script = """
        tell application "System Events"
            tell process "Control Center"
                -- This is a placeholder implementation
                -- Real implementation would require proper AppleScript or private APIs
            end tell
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            logger.error("❌ Failed to enable system DND: \(error[NSLocalizedDescriptionKey] as? String ?? String(describing: error))")
        } else {
            logger.info("🔇 System DND enabled")
        }
    }

    private func disableSystemDND() {
        // Disable system Do Not Disturb via AppleScript
        let script = """
        tell application "System Events"
            tell process "Control Center"
                -- This is a placeholder implementation
                -- Real implementation would require proper AppleScript or private APIs
            end tell
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            logger.error("❌ Failed to disable system DND: \(error[NSLocalizedDescriptionKey] as? String ?? String(describing: error))")
        } else {
            logger.info("🔊 System DND disabled")
        }
    }

}
