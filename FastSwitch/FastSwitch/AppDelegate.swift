import Cocoa
import Carbon.HIToolbox
import ApplicationServices
import UserNotifications
import Foundation
import UniformTypeIdentifiers

private let DISABLE_WALLPAPER = true




class AppDelegate: NSObject, NSApplicationDelegate, NotificationManagerDelegate, HotkeyManagerDelegate, AppSwitchingManagerDelegate, PersistenceManagerDelegate, UsageTrackingManagerDelegate, BreakReminderManagerDelegate, WellnessManagerDelegate, MenuBarManagerDelegate {
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
    
    // Track current notification mode
    private var currentNotificationMode: NotificationMode = .testing
    
    // Persistent storage
    private var usageHistory: UsageHistory = UsageHistory()
    private var deepFocusSessionStartTime: Date?
    
    // Break timer system (now handled by BreakReminderManager)
    private var customFocusDuration: TimeInterval = 3600 // Default 60 minutes
    
    // Wellness tracking (now handled by WellnessManager)
    
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
                print("⚠️ FastSwitch: Another instance is already running, exiting...")
                NSApp.terminate(nil)
                return
            }
        }
        
        print("🚀 FastSwitch: Starting up...")
        print("⏱️ FastSwitch: Action delay: \(actionDelay)s")
        
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

        // Setup menu bar
        MenuBarManager.shared.setupStatusBar()
        
        // Handle wallpaper menu state
        if DISABLE_WALLPAPER {
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
        
        // Initialize wellness tracking (opt-in, disabled by default)
        // WellnessManager.shared.setWellnessEnabled(true) // Uncomment to enable
        
        // Load motivational phrases
        loadMotivationalPhrases()
        
        // Wellness features now managed by WellnessManager
        
        // Auto-enable testing mode for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setNotificationIntervalTest()
        }
        
        // Wellness reminders now handled by WellnessManager
        
        #if DEBUG
        // Quick wellness testing - trigger all wellness questions for testing
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.startWellnessTestingMode()
        }
        #endif
        
        // Update initial menu state
        MenuBarManager.shared.updateConfigurationMenu(mode: .testing)

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
        stopUsageTracking()
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
            print("🎬 FastSwitch: Executing action: \(action)")
            switch action {
            case "action:meet-mic": toggleMeetMic()
            case "action:meet-cam": toggleMeetCam()
            case "action:deep-focus": toggleDeepFocus()
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
        print("🎤 FastSwitch: F5 pressed - Toggle Meet mic")
        
        // Automatically set call status when using Meet controls
        if chromeFrontTabIsMeet() {
            manualCallToggle = true
            print("🎤 FastSwitch: Meet detected, enabling call status")
        }
        
        AppSwitchingManager.shared.activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { 
                self.sendShortcut(letter: "d", command: true) // ⌘D
                self.manualCallToggle = true // Ensure call status is set
                print("🎤 FastSwitch: Sent ⌘D to toggle mic")
            }
        }
    }
    private func toggleMeetCam() {
        let chrome = "com.google.Chrome"
        print("📹 FastSwitch: F6 pressed - Toggle Meet camera")
        
        // Automatically set call status when using Meet controls
        if chromeFrontTabIsMeet() {
            manualCallToggle = true
            print("📹 FastSwitch: Meet detected, enabling call status")
        }
        
        AppSwitchingManager.shared.activateApp(bundleID: chrome) { [weak self] in
            guard let self = self else { return }
            if self.chromeFrontTabIsMeet() { 
                self.sendShortcut(letter: "e", command: true) // ⌘E
                self.manualCallToggle = true // Ensure call status is set
                print("📹 FastSwitch: Sent ⌘E to toggle camera")
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
        print("🧘 FastSwitch: F7 pressed - Toggle Deep Focus: \(isDeepFocusEnabled ? "ON" : "OFF")")
        
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
        print("🧘 FastSwitch: Activating Deep Focus...")
        
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
        
        print("✅ FastSwitch: Deep Focus enabled - macOS + Slack DND, 60min timer started")
    }
    
    private func disableDeepFocus() {
        print("🧘 FastSwitch: Deactivating Deep Focus...")
        
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
            
            print("✅ FastSwitch: Deep Focus disabled - macOS + Slack DND off (duration: \(minutes)min)")
            deepFocusSessionStartTime = nil
        }
        
        deepFocusStartTime = nil
    }
    
    private func updateStatusBarForFocus() {
        // Focus status is now handled by MenuBarManager
        MenuBarManager.shared.updateDeepFocusStatus(isDeepFocusEnabled)
    }
    
    private func enableSlackDND() {
        print("🧘 FastSwitch: Activating Slack DND...")
        
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
        print("✅ FastSwitch: DND command sent to Slack")
    }
    
    private func disableSlackDND() {
        print("🧘 FastSwitch: Deactivating Slack DND...")
        
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
        print("✅ FastSwitch: Slack DND disabled")
    }
    
    private func showDeepFocusCompletionNotification() {
        print("🧘 FastSwitch: 60min Deep Focus session completed")
        
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
        
        print("🎯 FastSwitch: Iniciando sesión personalizada de 45 minutos")
    }
    
    // MARK: - Wellness Tracking System
    private func scheduleWellnessQuestions() {
        // Check for wellness questions every 30 minutes
        wellnessQuestionTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.checkForWellnessQuestions()
        }
        
        print("🌱 FastSwitch: Sistema de bienestar inicializado")
    }
    
    private func checkForWellnessQuestions() {
        guard wellnessQuestionsEnabled else { return }
        
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // Record workday start on first activity of the day
        if !hasRecordedWorkdayStart {
            recordWorkdayStart()
        }
        
        // Check for different types of wellness questions based on time and context
        if shouldAskMateQuestion(at: now, hour: hour) {
            askMateQuestion()
        } else if shouldAskExerciseQuestion(at: now, hour: hour) {
            askExerciseQuestion()
        } else if shouldAskEnergyCheck(at: now, hour: hour) {
            askEnergyCheck()
        }
    }
    
    private func recordWorkdayStart() {
        let todayKey = getTodayKey()
        if var todayData = usageHistory.dailyData[todayKey] {
            todayData.workdayStart = Date()
            usageHistory.dailyData[todayKey] = todayData
            hasRecordedWorkdayStart = true
            if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
            print("🌅 FastSwitch: Inicio de jornada registrado")
        }
    }
    
    private func shouldAskMateQuestion(at now: Date, hour: Int) -> Bool {
        // Ask about mate/sugar every 2-3 hours during work hours (9-18)
        guard hour >= 9 && hour <= 18 else { return false }
        
        if let lastQuestion = lastMateQuestion {
            let timeSinceLastQuestion = now.timeIntervalSince(lastQuestion)
            return timeSinceLastQuestion >= 7200 // 2 hours
        }
        
        // First mate question of the day
        return hour >= 10
    }
    
    private func shouldAskExerciseQuestion(at now: Date, hour: Int) -> Bool {
        // Ask about exercise around 2 PM if not asked today
        guard hour >= 14 && hour <= 16 else { return false }
        
        if let lastQuestion = lastExerciseQuestion {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let questionDay = calendar.startOfDay(for: lastQuestion)
            return today > questionDay // Haven't asked today
        }
        
        return true // First time asking
    }
    
    private func shouldAskEnergyCheck(at now: Date, hour: Int) -> Bool {
        // Ask about energy when in long sessions without breaks
        let sessionDuration = UsageTrackingManager.shared.getCurrentSessionDuration()
        guard sessionDuration >= 7200 else { return false } // 2+ hours
        
        if let lastCheck = lastEnergyCheck {
            let timeSinceLastCheck = now.timeIntervalSince(lastCheck)
            return timeSinceLastCheck >= 5400 // 1.5 hours
        }
        
        return true // First energy check for long session
    }
    
    private func askMateQuestion() {
        lastMateQuestion = Date()
        
        let content = UNMutableNotificationContent()
        content.title = "🧉 Check de Mate y Azúcar"
        content.body = "¿Cuántos mates llevás hoy? ¿Con qué nivel de azúcar?\n\n⏰ Solo toma un segundo responder"
        self.addPhraseToNotification(content, context: "afternoon")
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Glass.aiff"))
        content.interruptionLevel = .active
        content.categoryIdentifier = "MATE_QUESTION"
        
        let noneAction = UNNotificationAction(identifier: "MATE_NONE", title: "🧉 0 termos", options: [])
        let lowAction = UNNotificationAction(identifier: "MATE_LOW", title: "🧉 1 termo", options: [])
        let mediumAction = UNNotificationAction(identifier: "MATE_MEDIUM", title: "🧉 2 termos", options: [])
        let highAction = UNNotificationAction(identifier: "MATE_HIGH", title: "🧉 3+ termos", options: [])
        
        let category = UNNotificationCategory(
            identifier: "MATE_QUESTION",
            actions: [noneAction, lowAction, mediumAction, highAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "mate-question-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando pregunta de mate: \(error)")
            } else {
                print("🧉 FastSwitch: Mate question sent")
            }
        }
    }
    
    private func askExerciseQuestion() {
        lastExerciseQuestion = Date()
        
        let content = UNMutableNotificationContent()
        content.title = "🏃 Check de Ejercicio"
        content.body = "¿Hiciste algo de ejercicio o movimiento hoy?\n\n💪 Cualquier actividad cuenta"
        self.addPhraseToNotification(content, context: "afternoon")
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Blow.aiff"))
        content.interruptionLevel = .active
        content.categoryIdentifier = "EXERCISE_QUESTION"
        
        let noAction = UNNotificationAction(identifier: "EXERCISE_NO", title: "❌ No", options: [])
        let lightAction = UNNotificationAction(identifier: "EXERCISE_LIGHT", title: "🚶 15min", options: [])
        let moderateAction = UNNotificationAction(identifier: "EXERCISE_MODERATE", title: "🏃 30min", options: [])
        let intenseAction = UNNotificationAction(identifier: "EXERCISE_INTENSE", title: "💪 45min+", options: [])
        
        let category = UNNotificationCategory(
            identifier: "EXERCISE_QUESTION",
            actions: [noAction, lightAction, moderateAction, intenseAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "exercise-question-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando pregunta de ejercicio: \(error)")
            } else {
                print("🏃 FastSwitch: Pregunta de ejercicio enviada")
            }
        }
    }
    
    private func askEnergyCheck() {
        lastEnergyCheck = Date()
        
        let content = UNMutableNotificationContent()
        content.title = "⚡ Check de Energía"
        content.body = "Llevás un rato trabajando... ¿Cómo está tu energía?\n\n🔋 Ayuda a mejorar tus patrones"
        self.addPhraseToNotification(content, context: "energy_check")
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Tink.aiff"))
        content.interruptionLevel = .active
        content.categoryIdentifier = "ENERGY_CHECK"
        
        let lowAction = UNNotificationAction(identifier: "ENERGY_LOW", title: "🔋 Bajo (1-3)", options: [])
        let mediumAction = UNNotificationAction(identifier: "ENERGY_MEDIUM", title: "🔋 Medio (4-6)", options: [])
        let highAction = UNNotificationAction(identifier: "ENERGY_HIGH", title: "🔋 Alto (7-10)", options: [])
        
        let category = UNNotificationCategory(
            identifier: "ENERGY_CHECK",
            actions: [lowAction, mediumAction, highAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "energy-check-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando check de energía: \(error)")
            } else {
                print("⚡ FastSwitch: Check de energía enviado")
            }
        }
    }
    
    // MARK: - Wellness Data Recording
    private func WellnessManager.shared.recordMate(thermosCount: Int) {
        let todayKey = getTodayKey()
        if var todayData = usageHistory.dailyData[todayKey] {
            let mateRecord = MateRecord(time: Date(), thermosCount: thermosCount, type: "mate")
            todayData.wellnessMetrics.mateRecords.append(mateRecord)
            usageHistory.dailyData[todayKey] = todayData
            if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
            
            todayMateCount += thermosCount
            updateMateReductionProgress()
            updateMateMenuStatus()
            
            print("🧉 FastSwitch: Mate registrado - Termos: \(thermosCount), Total hoy: \(todayMateCount)")
        } else {
            print("❌ FastSwitch: Error al registrar mate - día no encontrado")
        }
    }
    
    private func updateMateReductionProgress() {
        // Check if we should advance to next phase
        if mateReductionPlan.shouldAdvancePhase() {
            advanceMateReductionPhase()
        }
        
        // Check daily target
        let target = mateReductionPlan.getCurrentTargetThermos()
        if todayMateCount >= target {
            showMateTargetReachedNotification()
        }
    }
    
    private func advanceMateReductionPhase() {
        let newPhase = min(mateReductionPlan.currentPhase + 1, 3)
        mateReductionPlan.currentPhase = newPhase
        
        saveMateReductionPlan()
        showPhaseAdvancementNotification()
        scheduleMateReminders()
    }
    
    private func showMateTargetReachedNotification() {
        let target = mateReductionPlan.getCurrentTargetThermos()
        
        // Use NotificationManager for success notification
        NotificationManager.shared.scheduleSuccessNotification(
            title: "🎯 Objetivo de Mate Alcanzado",
            message: "Ya tomaste \(target) termos hoy. ¡Perfecto! Mantenete así hasta mañana."
        )
    }
    
    private func showPhaseAdvancementNotification() {
        let newTarget = mateReductionPlan.getCurrentTargetThermos()
        let schedule = mateReductionPlan.getCurrentSchedule().joined(separator: " • ")
        
        let content = UNMutableNotificationContent()
        content.title = "📈 Nueva Fase del Plan"
        content.body = "¡Avanzaste! Ahora tu objetivo son \(newTarget) termos por día.\n\nHorarios sugeridos: \(schedule)"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Submarine.aiff"))
        
        self.addPhraseToNotification(content, context: "mate_phase_advance")
        
        let request = UNNotificationRequest(
            identifier: "mate-phase-advance-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func scheduleMateReminders() {
        // Cancel existing timer
        mateScheduleTimer?.invalidate()
        
        let schedule = mateReductionPlan.getCurrentSchedule()
        let target = mateReductionPlan.getCurrentTargetThermos()
        
        print("🧉 FastSwitch: Programando recordatorios de mate para \(target) termos: \(schedule.joined(separator: ", "))")
        
        // Schedule notifications for each time slot
        for (index, timeString) in schedule.enumerated() {
            scheduleSpecificMateReminder(timeString: timeString, thermosNumber: index + 1, totalTarget: target)
        }
        
        // Schedule daily timer to check if we need new reminders
        mateScheduleTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkAndUpdateMateSchedule()
        }
    }
    
    private func scheduleSpecificMateReminder(timeString: String, thermosNumber: Int, totalTarget: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        guard let targetTime = formatter.date(from: timeString) else {
            print("❌ FastSwitch: Error parsing time: \(timeString)")
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let targetComponents = calendar.dateComponents([.hour, .minute], from: targetTime)
        
        guard let scheduledTime = calendar.nextDate(after: now,
                                                  matching: targetComponents,
                                                  matchingPolicy: .nextTime) else { return }
        
        // Add quick action buttons
        let recordMateAction = UNNotificationAction(
            identifier: "RECORD_MATE_ACTION",
            title: "✅ Tomé mi mate",
            options: []
        )
        
        let skipMateAction = UNNotificationAction(
            identifier: "SKIP_MATE_ACTION", 
            title: "⏭️ Saltear por ahora",
            options: []
        )
        
        let content = createWellnessNotification(
            type: .mate,
            title: "Hora del Mate \(thermosNumber)/\(totalTarget)",
            body: "Es hora de tu termo de mate (\(timeString)). Recordá: querés llegar a \(totalTarget) termos hoy.",
            categoryIdentifier: "MATE_REMINDER",
            actions: [recordMateAction, skipMateAction]
        )
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.hour, .minute], from: scheduledTime),
            repeats: true
        )
        
        let request = UNNotificationRequest(
            identifier: "mate-reminder-\(timeString)-\(thermosNumber)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error programando recordatorio de mate: \(error)")
            } else {
                print("✅ FastSwitch: Recordatorio de mate programado para \(timeString)")
            }
        }
    }
    
    private func checkAndUpdateMateSchedule() {
        // Reset daily count at midnight
        let calendar = Calendar.current
        if !calendar.isDate(Date(), equalTo: mateReductionPlan.startDate, toGranularity: .day) {
            todayMateCount = 0
        }
        
        // Check if we should advance phase
        if mateReductionPlan.shouldAdvancePhase() {
            advanceMateReductionPhase()
        }
    }
    
    private func saveMateReductionPlan() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(mateReductionPlan) {
            UserDefaults.standard.set(encoded, forKey: "MateReductionPlan")
            print("✅ FastSwitch: Plan de reducción de mate guardado")
        }
    }
    
    private func loadMateReductionPlan() {
        if let plan = PersistenceManager.shared.loadMateReductionPlan() {
            mateReductionPlan = plan
            print("✅ FastSwitch: Plan de reducción de mate cargado - Fase \(plan.currentPhase)")
        } else {
            // Initialize new plan
            mateReductionPlan = MateReductionPlan()
            saveMateReductionPlan()
            print("🆕 FastSwitch: Nuevo plan de reducción de mate iniciado")
        }
    }
    
    private func recordExercise(done: Bool, duration: Int, type: String, intensity: Int) {
        let todayKey = getTodayKey()
        if var todayData = usageHistory.dailyData[todayKey] {
            let exerciseRecord = ExerciseRecord(
                time: Date(),
                done: done,
                duration: duration,
                type: type,
                intensity: intensity
            )
            todayData.wellnessMetrics.exerciseRecords.append(exerciseRecord)
            usageHistory.dailyData[todayKey] = todayData
            if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
            
            print("🏃 FastSwitch: Ejercicio registrado - Hecho: \(done), Duración: \(duration)min, Tipo: \(type)")
        }
    }
    
    private func WellnessManager.shared.recordWellnessCheck(type: String, level: Int, context: String) {
        let todayKey = getTodayKey()
        if var todayData = usageHistory.dailyData[todayKey] {
            let wellnessCheck = WellnessCheck(time: Date(), type: type, level: level, context: context)
            
            switch type {
            case "energy":
                todayData.wellnessMetrics.energyLevels.append(wellnessCheck)
            case "stress":
                todayData.wellnessMetrics.stressLevels.append(wellnessCheck)
            case "mood":
                todayData.wellnessMetrics.moodChecks.append(wellnessCheck)
            default:
                print("⚠️ FastSwitch: Tipo de wellness check desconocido: \(type)")
                return
            }
            
            usageHistory.dailyData[todayKey] = todayData
            if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
            
            print("🌱 FastSwitch: Check de bienestar registrado - Tipo: \(type), Nivel: \(level), Contexto: \(context)")
        }
    }
    
    private func recordWellnessAction(_ action: String, completed: Bool) {
        let todayKey = getTodayKey()
        if var todayData = usageHistory.dailyData[todayKey] {
            let wellnessCheck = WellnessCheck(
                time: Date(),
                type: action,
                level: completed ? 10 : 0, // 10 if completed, 0 if skipped
                context: "wellness_reminder"
            )
            
            // For now, add to mood checks as a general wellness action
            // In a fuller implementation, you might want a separate array
            todayData.wellnessMetrics.moodChecks.append(wellnessCheck)
            
            usageHistory.dailyData[todayKey] = todayData
            if let todayData = usageHistory.dailyData[getTodayKey()] {
            PersistenceManager.shared.saveDailyData(todayData)
        }
            
            let status = completed ? "completada" : "salteada"
            print("🎯 FastSwitch: Acción de bienestar \(action) \(status)")
        }
    }
    
    // MARK: - Motivational Phrases System
    private func loadMotivationalPhrases() {
        // Try to load from external JSON file first
        if let phrasesFromFile = loadPhrasesFromFile() {
            motivationalPhrases = phrasesFromFile
            print("💡 FastSwitch: Frases cargadas desde archivo externo - \(motivationalPhrases.count) frases")
        } else {
            // Fallback to default phrases
            loadDefaultPhrases()
            print("💡 FastSwitch: Usando frases por defecto - \(motivationalPhrases.count) frases")
        }
    }
    
    private func loadPhrasesFromFile() -> [MotivationalPhrase]? {
        // Look for phrases.json in the same directory as the app
        let currentPath = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let phrasesPath = currentPath.appendingPathComponent("phrases.json")
        
        // Also try in the project directory for development
        let projectPath = URL(fileURLWithPath: "/Users/gaston/code/repos/fast-switch/phrases.json")
        
        let pathsToTry = [phrasesPath, projectPath]
        
        for path in pathsToTry {
            if FileManager.default.fileExists(atPath: path.path) {
                do {
                    let data = try Data(contentsOf: path)
                    let phrasesData = try JSONDecoder().decode(PhrasesData.self, from: data)
                    print("💡 FastSwitch: Frases cargadas desde: \(path.path)")
                    return phrasesData.phrases
                } catch {
                    print("⚠️ FastSwitch: Error cargando frases desde \(path.path): \(error)")
                }
            }
        }
        
        return nil
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
    
    private func scheduleEyeBreakReminder() {
        let actions = [
            UNNotificationAction(identifier: "EYE_BREAK_DONE", title: "✅ Miré lejos 20seg", options: []),
            UNNotificationAction(identifier: "EYE_BREAK_SKIP", title: "⏭️ Ahora no", options: [])
        ]
        
        let content = createWellnessNotification(
            type: .eyeBreak,
            title: "Descanso Visual",
            body: "Mirá algo a 20 metros de distancia por 20 segundos. Tus ojos necesitan este break.",
            categoryIdentifier: "EYE_BREAK",
            actions: actions
        )
        
        scheduleNotificationIn(content: content, seconds: 1200) // 20 minutos
    }
    
    private func schedulePosturalBreakReminder() {
        let actions = [
            UNNotificationAction(identifier: "POSTURE_BREAK_DONE", title: "🧘‍♂️ Me estiré", options: []),
            UNNotificationAction(identifier: "POSTURE_BREAK_SKIP", title: "⏭️ Después", options: [])
        ]
        
        let content = createWellnessNotification(
            type: .posturalBreak,
            title: "Movete y Estirate",
            body: "Parate, estirá los brazos, movete un poco. Tu columna lo necesita.",
            categoryIdentifier: "POSTURE_BREAK",
            actions: actions
        )
        
        scheduleNotificationIn(content: content, seconds: 1800) // 30 minutos
    }
    
    private func scheduleHydrationReminder() {
        let actions = [
            UNNotificationAction(identifier: "HYDRATION_DONE", title: "💧 Tomé agua", options: []),
            UNNotificationAction(identifier: "HYDRATION_SKIP", title: "⏭️ Ya tomé", options: [])
        ]
        
        let content = createWellnessNotification(
            type: .hydration,
            title: "Hidratate",
            body: "Tomá un vaso de agua. Mantenete hidratado para pensar mejor.",
            categoryIdentifier: "HYDRATION_REMINDER",
            actions: actions
        )
        
        scheduleNotificationIn(content: content, seconds: 2400) // 40 minutos
    }
    
    private func scheduleDeepBreathingReminder() {
        let actions = [
            UNNotificationAction(identifier: "BREATHING_DONE", title: "🫁 Respiré profundo", options: []),
            UNNotificationAction(identifier: "BREATHING_SKIP", title: "⏭️ Luego", options: [])
        ]
        
        let content = createWellnessNotification(
            type: .deepBreath,
            title: "Respirá Profundo",
            body: "3 respiraciones profundas. Inhalá 4seg, mantené 4seg, exhalá 4seg.",
            categoryIdentifier: "BREATHING_REMINDER",
            actions: actions
        )
        
        scheduleNotificationIn(content: content, seconds: 900) // 15 minutos
    }
    
    private func scheduleNotificationIn(content: UNMutableNotificationContent, seconds: TimeInterval) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "wellness-\(content.categoryIdentifier)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error programando \(content.categoryIdentifier): \(error)")
            } else {
                print("✅ FastSwitch: \(content.categoryIdentifier) programado para \(Int(seconds))s")
            }
        }
    }
    
    private func scheduleWellnessReminders() {
        print("🌱 FastSwitch: Iniciando sistema de recordatorios de bienestar")
        
        // Schedule different wellness reminders with staggered timing
        scheduleDeepBreathingReminder()     // 15 min
        scheduleEyeBreakReminder()          // 20 min
        schedulePosturalBreakReminder()     // 30 min  
        scheduleHydrationReminder()         // 40 min
        
        // Schedule recurring patterns
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.scheduleNextWellnessRound()
        }
    }
    
    private func scheduleNextWellnessRound() {
        // Randomize the order and timing to avoid predictability
        let baseDelay = 600 // 10 minutes base
        let randomDelay = Int.random(in: 0...600) // 0-10 minutes random
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(baseDelay + randomDelay)) {
            // Randomly pick one wellness reminder to schedule
            let reminders = [
                self.scheduleEyeBreakReminder,
                self.schedulePosturalBreakReminder, 
                self.scheduleHydrationReminder,
                self.scheduleDeepBreathingReminder
            ]
            
            reminders.randomElement()?()
        }
    }

    // MARK: - Quick Testing Mode (Debug Only)
    private func startWellnessTestingMode() {
        guard wellnessQuestionsEnabled else { return }
        
        print("🧪 FastSwitch: INICIANDO MODO DE TESTING RÁPIDO")
        print("🧪 Se enviará una notificación cada 5 segundos para probar el sistema")
        
        // Test mate question after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            print("🧪 Testing: Pregunta de mate")
            self.askMateQuestion()
        }
        
        // Test exercise question after 12 seconds  
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            print("🧪 Testing: Pregunta de ejercicio")
            self.askExerciseQuestion()
        }
        
        // Test energy check after 19 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 19) {
            print("🧪 Testing: Check de energía")
            self.askEnergyCheck()
        }
        
        // Show testing summary after 26 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 26) {
            self.showTestingSummary()
        }
    }
    
    private func showTestingSummary() {
        print("🧪 FastSwitch: TESTING COMPLETADO")
        saveTodayData()
        
        let content = UNMutableNotificationContent()
        content.title = "🧪 Testing Completado"
        content.body = "¡Sistema de bienestar testeado exitosamente!\n\n✅ Preguntas de mate, ejercicio y energía funcionando\n💾 Datos guardados para exportación\n\n📊 Prueba ahora: Menu → Reportes → Exportar Datos"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Crystal.aiff"))
        content.interruptionLevel = .active
        
        let request = UNNotificationRequest(
            identifier: "testing-complete-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando resumen de testing: \(error)")
            } else {
                print("✅ FastSwitch: Resumen de testing enviado")
            }
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
        print("🖥️ Paperlike \(paperlikeEnabled ? "ON" : "OFF")")
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
        print("🎛️ Grayscale global \(grayscaleOn ? "ON" : "OFF")")
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
                print("Spotify no inició a tiempo; omitido play/pause.")
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
                print("AppleScript error:", error)
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
        
        print("💾 FastSwitch: Datos de hoy guardados")
    }
    
    // MARK: - Usage Tracking
    
    
    
    private func checkUserActivity() {
        let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let keyboardIdleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        
        let minIdleTime = min(idleTime, keyboardIdleTime)
        let currentTime = Date()
        
        // Track app usage
        trackAppUsage()
        
        // Check if user is in a call
        updateCallStatus()
        
        // Check for end of workday for daily reflection
        if detectEndOfWorkday() {
            WellnessManager.shared.askDailyReflection()
        }
        
        let effectiveIdleThreshold = isInCall ? callIdleThreshold : idleThreshold
        let sessionDuration = UsageTrackingManager.shared.getCurrentSessionDuration()
        
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
            print("😴 FastSwitch: Usuario inactivo (umbral: \(Int(effectiveIdleThreshold))s)")
            
            if !isCurrentlyOnBreak {
                BreakReminderManager.shared.startBreak()
            }
            
            updateStatusBarTitle(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
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
        if BreakReminderManager.shared.isBreakTimerActive, let startTime = breakTimerStartTime {
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
            if AppSwitchingManager.shared.isAppRunning(bundleID: bundleID) {
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
        content.badge = NSNumber(value: 1)
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
        sendBreakNotification(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration(),
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
            self.sendBreakNotification(sessionDuration: self.UsageTrackingManager.shared.getCurrentSessionDuration(),
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
    
    
    // MARK: - Break and Session Tracking
    private func BreakReminderManager.shared.startBreak() {
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
    
    private func BreakReminderManager.shared.endBreak() {
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
    
    
    private func WellnessManager.shared.askDailyReflection() {
        print("📝 FastSwitch: Pregunta de reflexión diaria")
        
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
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error enviando reflexión diaria: \(error)")
            } else {
                print("✅ FastSwitch: Reflexión diaria enviada")
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
        print("📊 FastSwitch: Mostrando dashboard diario")
        
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
            let title = "F→ \(callIndicator)\(timeString)"
            MenuBarManager.shared.updateTitle(title)
            MenuBarManager.shared.updateSessionTime(duration: sessionDuration, isInCall: self.isInCall)
        }
    }
    
    private func updateMenuItems(sessionDuration: TimeInterval) {
        // Menu item updates now handled by MenuBarManager
        MenuBarManager.shared.updateCallStatus(manualCallToggle)
        MenuBarManager.shared.updateDeepFocusStatus(isDeepFocusEnabled)
    }
    
    @objc private func toggleCallStatus() {
        let newStatus = UsageTrackingManager.shared.toggleCallStatus()
        manualCallToggle = newStatus
        print("🔄 FastSwitch: Toggle manual de llamada: \(newStatus)")
    }
    
    @objc private func toggleDeepFocusFromMenu() {
        self.toggleDeepFocus()
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
        UsageTrackingManager.shared.resetSession()
        sentNotificationIntervals.removeAll()
        
        // Reset break and session tracking
        BreakReminderManager.shared.resetBreakTracking()
        
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
            print("✅ FastSwitch: Datos exportados a: \(exportURL.path)")
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
    
    // MARK: - NotificationManagerDelegate
    func notificationManager(_ manager: NotificationManager, shouldPresentNotification notification: UNNotification) -> UNNotificationPresentationOptions {
        // Show notification even when app is active
        return [.banner, .sound, .badge]
    }
    
    func notificationManager(_ manager: NotificationManager, didReceiveAction actionId: String, with response: UNNotificationResponse) {
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
            self.stopStickyDeepFocusNotification()
            // Restart 60-minute timer
            deepFocusTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
                self?.showDeepFocusCompletionNotification()
            }
            NSApp.dockTile.badgeLabel = nil
            
        case "TAKE_BREAK_ACTION":
            print("☕ FastSwitch: Usuario eligió tomar descanso")
            // Stop sticky notifications since user clicked
            self.stopStickyDeepFocusNotification()
            // Disable Deep Focus
            if isDeepFocusEnabled {
                self.toggleDeepFocus()
            }
            NSApp.dockTile.badgeLabel = nil
            
        case "DISMISS_FOCUS_ACTION":
            print("✅ FastSwitch: Usuario confirmó notificación Deep Focus")
            // Stop sticky notifications since user clicked
            self.stopStickyDeepFocusNotification()
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
            self.BreakReminderManager.shared.startBreakTimer(duration: 900) // 15 minutes
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
            self.stopStickyDeepFocusNotification()
            // Restart with 60 minutes
            self.setCustomFocusDuration(3600)
            deepFocusTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
                self?.showDeepFocusCompletionNotification()
            }
            NSApp.dockTile.badgeLabel = nil
            
        case "TAKE_15MIN_BREAK_ACTION":
            print("☕ FastSwitch: Usuario eligió tomar descanso de 15min")
            self.stopStickyDeepFocusNotification()
            if isDeepFocusEnabled {
                self.toggleDeepFocus() // Disable deep focus
            }
            self.BreakReminderManager.shared.startBreakTimer(duration: 900) // 15 minutes
            NSApp.dockTile.badgeLabel = nil
            
        case "SHOW_SESSION_STATS_ACTION":
            print("📊 FastSwitch: Usuario solicitó estadísticas de sesión")
            self.stopStickyDeepFocusNotification()
            showDailyDashboard()
            NSApp.dockTile.badgeLabel = nil
            
        case "SET_CUSTOM_FOCUS_ACTION":
            print("🎯 FastSwitch: Usuario eligió duración personalizada")
            self.stopStickyDeepFocusNotification()
            self.showCustomFocusDurationOptions()
            NSApp.dockTile.badgeLabel = nil
            
        // Break Timer Complete Actions
        case "BACK_TO_WORK_ACTION":
            print("🏃 FastSwitch: Usuario volvió al trabajo")
            self.BreakReminderManager.shared.stopBreakTimer()
            NSApp.dockTile.badgeLabel = nil
            
        case "EXTEND_BREAK_ACTION":
            print("☕ FastSwitch: Usuario extendió descanso 5min")
            self.BreakReminderManager.shared.startBreakTimer(duration: 300) // 5 more minutes
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
            
        // Daily Reflection Actions
        case "WRITE_JOURNAL_ACTION":
            print("✍️ FastSwitch: Usuario eligió escribir bitácora completa")
            openJournalInterface()
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_PRODUCTIVE":
            print("💪 FastSwitch: Usuario se sintió productivo")
            _ = WellnessManager.shared.saveDailyReflection(mood: "productive", notes: "Día productivo")
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_BALANCED":
            print("⚖️ FastSwitch: Usuario se sintió equilibrado")
            _ = WellnessManager.shared.saveDailyReflection(mood: "balanced", notes: "Día equilibrado")
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_TIRED":
            print("😴 FastSwitch: Usuario se sintió cansado")
            _ = WellnessManager.shared.saveDailyReflection(mood: "tired", notes: "Día cansado")
            NSApp.dockTile.badgeLabel = nil
            
        case "MOOD_STRESSED":
            print("😤 FastSwitch: Usuario se sintió estresado")
            _ = WellnessManager.shared.saveDailyReflection(mood: "stressed", notes: "Día estresado")
            NSApp.dockTile.badgeLabel = nil
            
        case "START_REFLECTION_ACTION":
            print("📝 FastSwitch: Usuario inició reflexión desde dashboard")
            WellnessManager.shared.askDailyReflection()
            NSApp.dockTile.badgeLabel = nil
            
        // Wellness Question Actions - Mate and Sugar
        case "MATE_NONE":
            print("🧉 FastSwitch: Usuario reportó 0 termos")
            self.WellnessManager.shared.recordMate(thermosCount: 0)
            NSApp.dockTile.badgeLabel = nil
            
        case "MATE_LOW":
            print("🧉 FastSwitch: Usuario reportó 1 termo")
            self.WellnessManager.shared.recordMate(thermosCount: 1)
            NSApp.dockTile.badgeLabel = nil
            
        case "MATE_MEDIUM":
            print("🧉 FastSwitch: Usuario reportó 2 termos")
            self.WellnessManager.shared.recordMate(thermosCount: 2)
            NSApp.dockTile.badgeLabel = nil
            
        case "MATE_HIGH":
            print("🧉 FastSwitch: Usuario reportó 3+ termos")
            self.WellnessManager.shared.recordMate(thermosCount: 3)
            NSApp.dockTile.badgeLabel = nil
            
        // New Mate Reminder Actions
        case "RECORD_MATE_ACTION":
            print("✅ FastSwitch: Usuario registró mate desde recordatorio")
            self.WellnessManager.shared.recordMate(thermosCount: 1)
            NSApp.dockTile.badgeLabel = nil
            
        case "SKIP_MATE_ACTION":
            print("⏭️ FastSwitch: Usuario salteó mate desde recordatorio")
            NSApp.dockTile.badgeLabel = nil
            
        // Wellness Question Actions - Exercise
        case "EXERCISE_NO":
            print("🏃 FastSwitch: Usuario reportó no ejercicio")
            self.recordExercise(done: false, duration: 0, type: "none", intensity: 0)
            NSApp.dockTile.badgeLabel = nil
            
        case "EXERCISE_LIGHT":
            print("🏃 FastSwitch: Usuario reportó ejercicio ligero 15min")
            self.recordExercise(done: true, duration: 15, type: "light", intensity: 1)
            NSApp.dockTile.badgeLabel = nil
            
        case "EXERCISE_MODERATE":
            print("🏃 FastSwitch: Usuario reportó ejercicio moderado 30min")
            self.recordExercise(done: true, duration: 30, type: "moderate", intensity: 2)
            NSApp.dockTile.badgeLabel = nil
            
        case "EXERCISE_INTENSE":
            print("🏃 FastSwitch: Usuario reportó ejercicio intenso 45min+")
            self.recordExercise(done: true, duration: 45, type: "intense", intensity: 3)
            NSApp.dockTile.badgeLabel = nil
            
        // Wellness Question Actions - Energy
        case "ENERGY_LOW":
            print("⚡ FastSwitch: Usuario reportó energía baja")
            self.WellnessManager.shared.recordWellnessCheck(type: "energy", level: 2, context: "work_session")
            NSApp.dockTile.badgeLabel = nil
            
        case "ENERGY_MEDIUM":
            print("⚡ FastSwitch: Usuario reportó energía media")
            self.WellnessManager.shared.recordWellnessCheck(type: "energy", level: 5, context: "work_session")
            NSApp.dockTile.badgeLabel = nil
            
        case "ENERGY_HIGH":
            print("⚡ FastSwitch: Usuario reportó energía alta")
            self.WellnessManager.shared.recordWellnessCheck(type: "energy", level: 8, context: "work_session")
            NSApp.dockTile.badgeLabel = nil
            
        // New Wellness Actions
        case "EYE_BREAK_DONE":
            print("👁️ FastSwitch: Usuario completó descanso visual")
            self.recordWellnessAction("eye_break", completed: true)
            NSApp.dockTile.badgeLabel = nil
            
        case "EYE_BREAK_SKIP":
            print("👁️ FastSwitch: Usuario saltó descanso visual")
            self.recordWellnessAction("eye_break", completed: false)
            NSApp.dockTile.badgeLabel = nil
            
        case "POSTURE_BREAK_DONE":
            print("🧘‍♂️ FastSwitch: Usuario se estiró")
            self.recordWellnessAction("posture_break", completed: true)
            NSApp.dockTile.badgeLabel = nil
            
        case "POSTURE_BREAK_SKIP":
            print("🧘‍♂️ FastSwitch: Usuario saltó estiramiento")
            self.recordWellnessAction("posture_break", completed: false)
            NSApp.dockTile.badgeLabel = nil
            
        case "HYDRATION_DONE":
            print("💧 FastSwitch: Usuario tomó agua")
            self.recordWellnessAction("hydration", completed: true)
            NSApp.dockTile.badgeLabel = nil
            
        case "HYDRATION_SKIP":
            print("💧 FastSwitch: Usuario saltó hidratación")
            self.recordWellnessAction("hydration", completed: false)
            NSApp.dockTile.badgeLabel = nil
            
        case "BREATHING_DONE":
            print("🫁 FastSwitch: Usuario respiró profundo")
            self.recordWellnessAction("breathing", completed: true)
            NSApp.dockTile.badgeLabel = nil
            
        case "BREATHING_SKIP":
            print("🫁 FastSwitch: Usuario saltó respiración")
            self.recordWellnessAction("breathing", completed: false)
            NSApp.dockTile.badgeLabel = nil
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            print("👆 FastSwitch: Usuario tocó la notificación")
            // Stop sticky notifications based on notification type
            let categoryIdentifier = response.notification.request.content.categoryIdentifier
            if categoryIdentifier == "DEEP_FOCUS_COMPLETE" {
                self.stopStickyDeepFocusNotification()
            } else if categoryIdentifier == "BREAK_REMINDER" {
                stopStickyBreakNotifications()
            }
            NSApp.dockTile.badgeLabel = nil
            
        default:
            break
        }
    }
    
    // MARK: - Daily Reflection and Journal Functions
    private func _ = WellnessManager.shared.saveDailyReflection(mood: String, notes: String) {
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
        
        print("✅ FastSwitch: Reflexión diaria guardada - Mood: \(mood)")
        
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
        print("✍️ FastSwitch: Abriendo interfaz de bitácora")
        
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
                print("📝 FastSwitch: Usuario canceló o no escribió nada")
            }
        } else if let error = error {
            print("❌ FastSwitch: Error en script de bitácora: \(error)")
            
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
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error programando snooze: \(error)")
            } else {
                print("✅ FastSwitch: Snooze programado para 5 minutos")
            }
        }
    }
    
    // MARK: - Mate Reduction Plan Functions
    @objc private func showMateProgress() {
        let target = mateReductionPlan.getCurrentTargetThermos()
        let schedule = mateReductionPlan.getCurrentSchedule().joined(separator: " • ")
        let phase = mateReductionPlan.currentPhase + 1
        
        let content = UNMutableNotificationContent()
        content.title = "🧉 Estado del Plan de Mate"
        content.body = """
        Fase \(phase)/4: \(target) termos por día
        Total hoy: \(todayMateCount)/\(target)
        
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
        // Mate status now handled by MenuBarManager
        let target = mateReductionPlan.getCurrentTargetThermos()
        let phase = mateReductionPlan.currentPhase + 1
        MenuBarManager.shared.updateMateStatus(phase: phase, current: todayMateCount, target: target)
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
        } else {
            let fallback = ["Concéntrate en el proceso, no en el resultado",
                            "La consistencia vence al talento",
                            "Pequeños pasos, grandes logros",
                            "Cada día es una nueva oportunidad",
                            "El descanso es parte del trabajo"]
            let list = motivationalPhrases.isEmpty ? fallback : motivationalPhrases.map { $0.text }
            WallpaperPhraseManager.shared.start(phrases: list, interval: WallpaperPhraseManager.shared.interval)
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

extension AppDelegate: PersistenceManagerDelegate {
    func persistenceManager(_ manager: PersistenceManager, didLoadUsageHistory history: UsageHistory) {
        usageHistory = history
        print("📂 FastSwitch: Usage history loaded via PersistenceManager")
    }
    
    func persistenceManager(_ manager: PersistenceManager, didFailWithError error: Error) {
        print("❌ FastSwitch: PersistenceManager error: \(error.localizedDescription)")
        
        // Show error notification
        NotificationManager.shared.scheduleErrorNotification(
            title: "💾 Data Error",
            message: "Failed to save/load data: \(error.localizedDescription)"
        )
    }
}

// MARK: - UsageTrackingManagerDelegate

extension AppDelegate: UsageTrackingManagerDelegate {
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
        
        print("📞 FastSwitch: Call status changed: \(inCall)")
    }
}

// MARK: - BreakReminderManagerDelegate

extension AppDelegate: BreakReminderManagerDelegate {
    func breakReminderManager(_ manager: BreakReminderManager, didStartBreak duration: TimeInterval) {
        // Update UI to reflect break state
        updateMenuItems(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
        print("☕ FastSwitch: Break started via BreakReminderManager")
    }
    
    func breakReminderManager(_ manager: BreakReminderManager, didEndBreak duration: TimeInterval) {
        // Update UI to reflect work state
        updateMenuItems(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration())
        
        let minutes = Int(duration / 60)
        print("🔄 FastSwitch: Break ended after \(minutes) minutes via BreakReminderManager")
    }
    
    func breakReminderManager(_ manager: BreakReminderManager, didSendBreakNotification sessionDuration: TimeInterval) {
        // Log break notification sent
        let minutes = Int(sessionDuration / 60)
        print("📢 FastSwitch: Break notification sent for \(minutes) minute session")
    }
    
    func breakReminderManager(_ manager: BreakReminderManager, needsNotification request: UNNotificationRequest) {
        // Send notification via system
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error sending break notification: \(error)")
            } else {
                print("✅ FastSwitch: Break notification sent successfully")
            }
        }
    }
}

// MARK: - WellnessManagerDelegate

extension AppDelegate: WellnessManagerDelegate {
    func wellnessManager(_ manager: WellnessManager, needsNotification request: UNNotificationRequest) {
        // Send wellness notification via system
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ FastSwitch: Error sending wellness notification: \(error)")
            } else {
                print("✅ FastSwitch: Wellness notification sent successfully")
            }
        }
    }
    
    func wellnessManager(_ manager: WellnessManager, didUpdateMateProgress thermos: Int, target: Int) {
        // Update mate progress in menu (method will be extracted to MenuBarManager)
        print("🧉 FastSwitch: Mate progress updated: \(thermos)/\(target)")
    }
    
    func wellnessManager(_ manager: WellnessManager, didAdvancePhase newPhase: Int) {
        // Update UI for phase advancement
        print("📈 FastSwitch: Mate reduction advanced to phase \(newPhase)")
    }
    
    func wellnessManager(_ manager: WellnessManager, didSaveDailyReflection reflection: DailyReflection) {
        // Save reflection to today's data
        let todayKey = getTodayKey()
        guard var todayData = usageHistory.dailyData[todayKey] else { return }
        
        todayData.dailyReflection = reflection
        usageHistory.dailyData[todayKey] = todayData
        PersistenceManager.shared.saveDailyData(todayData)
        
        print("📝 FastSwitch: Daily reflection saved via WellnessManager")
    }
}

// MARK: - MenuBarManagerDelegate

extension AppDelegate: MenuBarManagerDelegate {
    func menuBarManager(_ manager: MenuBarManager, requestAutomationPermissions: Void) {
        requestAutomationPrompts()
    }
    
    func menuBarManager(_ manager: MenuBarManager, toggleCallStatus: Void) {
        toggleCallStatus()
    }
    
    func menuBarManager(_ manager: MenuBarManager, toggleDeepFocus: Void) {
        toggleDeepFocusFromMenu()
    }
    
    func menuBarManager(_ manager: MenuBarManager, resetSession: Void) {
        resetSession()
    }
    
    func menuBarManager(_ manager: MenuBarManager, showDashboard: Void) {
        showDashboardManually()
    }
    
    func menuBarManager(_ manager: MenuBarManager, showWeeklyReport: Void) {
        showWeeklyReport()
    }
    
    func menuBarManager(_ manager: MenuBarManager, showYearlyReport: Void) {
        showYearlyReport()
    }
    
    func menuBarManager(_ manager: MenuBarManager, exportData: Void) {
        exportUsageData()
    }
    
    func menuBarManager(_ manager: MenuBarManager, showMateProgress: Void) {
        showMateProgress()
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
