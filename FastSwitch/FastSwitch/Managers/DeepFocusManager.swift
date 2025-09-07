//
//  DeepFocusManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import UserNotifications
import os.log

// MARK: - DeepFocusManager Protocol

protocol DeepFocusManagerDelegate: AnyObject {
    func deepFocusManager(_ manager: DeepFocusManager, didToggleFocus enabled: Bool)
    func deepFocusManager(_ manager: DeepFocusManager, needsSlackDND enabled: Bool)
    func deepFocusManager(_ manager: DeepFocusManager, needsSystemDND enabled: Bool)
    func deepFocusManager(_ manager: DeepFocusManager, needsNotification request: UNNotificationRequest)
    func deepFocusManager(_ manager: DeepFocusManager, didCompleteSession duration: TimeInterval)
}

// MARK: - DeepFocusManager

final class DeepFocusManager: NSObject {
    
    // MARK: - Singleton
    static let shared = DeepFocusManager()
    
    // MARK: - Properties
    weak var delegate: DeepFocusManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "DeepFocusManager")
    
    // Focus state
    private(set) var isEnabled: Bool = false
    private var focusStartTime: Date?
    private var sessionStartTime: Date?
    private var customDuration: TimeInterval = 3600 // Default 60 minutes
    
    // Timers
    private var focusTimer: Timer?
    private var notificationTimer: Timer?
    
    // Notification settings
    private let stickyNotificationInterval: TimeInterval = 15.0 // Re-send every 15 seconds
    private let stickyMaxDuration: TimeInterval = 60.0 // Stop after 1 minute
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        logger.info("🧘 DeepFocusManager initialized")
    }
    
    // MARK: - Public API
    
    func toggleDeepFocus() {
        if isEnabled {
            disableFocus()
        } else {
            enableFocus()
        }
    }
    
    func enableFocus(duration: TimeInterval? = nil) {
        guard !isEnabled else { return }
        
        let focusDuration = duration ?? customDuration
        isEnabled = true
        focusStartTime = Date()
        sessionStartTime = Date()
        
        logger.info("🧘 FastSwitch: Activating Deep Focus...")
        
        // Enable system DND
        delegate?.deepFocusManager(self, needsSystemDND: true)
        
        // Enable Slack DND
        delegate?.deepFocusManager(self, needsSlackDND: true)
        
        // Start focus timer
        startFocusTimer(duration: focusDuration)
        
        // Start sticky notifications
        startStickyNotifications()
        
        delegate?.deepFocusManager(self, didToggleFocus: true)
        
        logger.info("✅ FastSwitch: Deep Focus enabled - macOS + Slack DND, \(Int(focusDuration/60))min timer started")
    }
    
    func disableFocus() {
        guard isEnabled else { return }
        
        logger.info("🧘 FastSwitch: Deactivating Deep Focus...")
        
        isEnabled = false
        let sessionDuration = sessionStartTime != nil ? Date().timeIntervalSince(sessionStartTime!) : 0
        
        // Stop timers
        stopFocusTimer()
        stopStickyNotifications()
        
        // Disable system DND
        delegate?.deepFocusManager(self, needsSystemDND: false)
        
        // Disable Slack DND
        delegate?.deepFocusManager(self, needsSlackDND: false)
        
        if sessionDuration > 0 {
            let minutes = Int(sessionDuration / 60)
            logger.info("✅ FastSwitch: Deep Focus disabled - macOS + Slack DND off (duration: \(minutes)min)")
            delegate?.deepFocusManager(self, didCompleteSession: sessionDuration)
        }
        
        focusStartTime = nil
        sessionStartTime = nil
        
        delegate?.deepFocusManager(self, didToggleFocus: false)
    }
    
    func setCustomDuration(_ duration: TimeInterval) {
        customDuration = duration
        logger.info("🎯 FastSwitch: Custom focus duration configured: \(Int(duration / 60))min")
    }
    
    func getRemainingTime() -> TimeInterval {
        guard let startTime = focusStartTime, isEnabled else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, customDuration - elapsed)
    }
    
    func getCurrentSessionDuration() -> TimeInterval {
        guard let startTime = sessionStartTime, isEnabled else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Convenience Methods
    
    func start45MinuteSession() {
        setCustomDuration(2700) // 45 minutes
        enableFocus()
        logger.info("🎯 FastSwitch: Starting custom 45-minute session")
    }
    
    func start60MinuteSession() {
        setCustomDuration(3600) // 60 minutes
        enableFocus()
    }
    
    func start90MinuteSession() {
        setCustomDuration(5400) // 90 minutes
        enableFocus()
    }
    
    // MARK: - Private Methods
    
    private func startFocusTimer(duration: TimeInterval) {
        stopFocusTimer() // Stop any existing timer
        
        focusTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.handleFocusTimerExpired()
        }
    }
    
    private func stopFocusTimer() {
        focusTimer?.invalidate()
        focusTimer = nil
    }
    
    private func handleFocusTimerExpired() {
        logger.info("🧘 FastSwitch: 60min Deep Focus session completed")
        
        // Send completion notification
        sendCompletionNotification()
        
        // Auto-disable focus
        disableFocus()
    }
    
    private func startStickyNotifications() {
        sendDeepFocusNotification()
        
        notificationTimer = Timer.scheduledTimer(withTimeInterval: stickyNotificationInterval, repeats: true) { [weak self] timer in
            guard let self = self, let startTime = self.focusStartTime else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > self.stickyMaxDuration {
                self.logger.info("🧘 FastSwitch: Sticky notification timer expired after 1 minute")
                timer.invalidate()
                return
            }
            
            self.logger.info("🧘 FastSwitch: Re-sending sticky notification (\(Int(elapsed))s elapsed)")
            self.sendDeepFocusNotification()
        }
    }
    
    private func stopStickyNotifications() {
        logger.info("🧘 FastSwitch: Stopping sticky Deep Focus notifications")
        notificationTimer?.invalidate()
        notificationTimer = nil
        
        // Remove any pending notifications
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["deep-focus-sticky"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["deep-focus-sticky"])
    }
    
    private func sendDeepFocusNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🧘 Deep Focus Mode Active"
        content.body = """
        You are in Deep Focus mode. Notifications are silenced.
        Stay focused on your important work.
        """
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "DEEP_FOCUS"
        
        // Actions
        let extendAction = UNNotificationAction(
            identifier: "EXTEND_FOCUS",
            title: "⏰ Extend (15m)",
            options: []
        )
        
        let endAction = UNNotificationAction(
            identifier: "END_FOCUS",
            title: "✅ End Focus",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "DEEP_FOCUS",
            actions: [extendAction, endAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "deep-focus-sticky",
            content: content,
            trigger: nil // Show immediately
        )
        
        delegate?.deepFocusManager(self, needsNotification: request)
    }
    
    private func sendCompletionNotification() {
        let sessionDuration = getCurrentSessionDuration()
        let minutes = Int(sessionDuration / 60)
        
        let content = UNMutableNotificationContent()
        content.title = "✅ Deep Focus Session Complete"
        content.body = "Great work! You focused for \(minutes) minutes. Take a well-deserved break."
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(
            identifier: "deep-focus-completed-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        delegate?.deepFocusManager(self, needsNotification: request)
    }
    
    // MARK: - Notification Actions
    
    func handleNotificationAction(_ actionId: String) {
        switch actionId {
        case "EXTEND_FOCUS":
            extendFocus(by: 900) // 15 minutes
        case "END_FOCUS":
            disableFocus()
        default:
            break
        }
    }
    
    private func extendFocus(by duration: TimeInterval) {
        guard isEnabled else { return }
        
        // Extend the custom duration
        customDuration += duration
        
        // Restart timer with new duration
        if let startTime = focusStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = customDuration - elapsed
            if remaining > 0 {
                startFocusTimer(duration: remaining)
            }
        }
        
        let minutes = Int(duration / 60)
        logger.info("⏰ FastSwitch: Deep Focus extended by \(minutes) minutes")
    }
}