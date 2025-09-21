//
//  BreakReminderManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import UserNotifications
import os.log

// MARK: - BreakReminderManager Protocol

protocol BreakReminderManagerDelegate: AnyObject {
    func breakReminderManager(_ manager: BreakReminderManager, didStartBreak duration: TimeInterval)
    func breakReminderManager(_ manager: BreakReminderManager, didEndBreak duration: TimeInterval)
    func breakReminderManager(_ manager: BreakReminderManager, didSendBreakNotification sessionDuration: TimeInterval)
    func breakReminderManager(_ manager: BreakReminderManager, needsNotification request: UNNotificationRequest)
}

// MARK: - BreakReminderManager

final class BreakReminderManager: NSObject {
    
    // MARK: - Singleton
    static let shared = BreakReminderManager()
    
    // MARK: - Properties
    weak var delegate: BreakReminderManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "BreakReminderManager")
    
    // Break state
    private var isCurrentlyOnBreak: Bool = false
    private var breakStartTime: Date?
    private var totalBreakTime: TimeInterval = 0
    private var breaksTaken: [SessionRecord] = []
    
    // Break timer system
    private var breakTimer: Timer?
    private var breakTimerStartTime: Date?
    
    // Sticky notifications
    private var stickyBreakStartTime: Date?
    private var stickyBreakTimer: Timer?
    private let stickyRepeatInterval: TimeInterval = 15      // reintentar cada 15s
    private let stickyMaxDuration: TimeInterval = 60 * 60    // tope 60 min
    private let stickyBreakNotificationID = "break-sticky"   // ID fijo para poder reemplazar/limpiar
    private var stickyRemindersEnabled: Bool = false  // Disabled since native Alerts work better
    
    // Configuration
    private var notificationIntervals: [TimeInterval] = [60, 300, 600] // 1min, 5min, 10min para testing
    private var notificationsEnabled: Bool = true
    private var sentNotificationIntervals: Set<TimeInterval> = []
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        logger.info("⏰ BreakReminderManager initialized")
    }
    
    // MARK: - Public API
    
    /// Check if currently on break
    func isOnBreak() -> Bool {
        return isCurrentlyOnBreak
    }
    
    /// Get total break time for today
    func getTotalBreakTime() -> TimeInterval {
        var total = totalBreakTime
        
        // Add current break time if on break
        if let breakStart = breakStartTime {
            total += Date().timeIntervalSince(breakStart)
        }
        
        return total
    }
    
    /// Get breaks taken today
    func getBreaksTaken() -> [SessionRecord] {
        return breaksTaken
    }
    
    /// Reset break tracking for new session
    func resetBreakTracking() {
        breaksTaken.removeAll()
        isCurrentlyOnBreak = false
        breakStartTime = nil
        totalBreakTime = 0
        sentNotificationIntervals.removeAll()
        
        // Stop any active timers
        breakTimer?.invalidate()
        breakTimer = nil
        breakTimerStartTime = nil
        
        logger.info("🔄 Reset break tracking")
    }
    
    /// Configure notification intervals
    func setNotificationIntervals(_ intervals: [TimeInterval]) {
        notificationIntervals = intervals
        logger.info("⚙️ Updated notification intervals: \(intervals.map { Int($0) })s")
    }
    
    /// Enable/disable notifications
    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        logger.info("🔔 Notifications \(enabled ? "enabled" : "disabled")")
    }
    
    /// Check for break notifications based on session duration
    func checkForBreakNotification(sessionDuration: TimeInterval) {
        guard notificationsEnabled else {
            logger.debug("🔕 Notifications disabled")
            return
        }
        
        logger.debug("🔍 Checking break notifications for session: \(Int(sessionDuration))s")
        
        for interval in notificationIntervals {
            if sessionDuration >= interval && !sentNotificationIntervals.contains(interval) {
                logger.info("⏰ Break notification triggered for interval: \(interval)s")
                sentNotificationIntervals.insert(interval)
                sendBreakNotification(sessionDuration: sessionDuration)
                break
            }
        }
    }
    
    /// Send break notification
    func sendBreakNotification(sessionDuration: TimeInterval, overrideIdentifier: String? = nil) {
        let notificationId = overrideIdentifier ?? "break-reminder-\(Int(Date().timeIntervalSince1970))"
        let sessionMinutes = Int(sessionDuration / 60)
        
        logger.info("📢 Sending break notification (session: \(sessionMinutes)m)")
        
        let content = UNMutableNotificationContent()
        content.title = "⏰ Time for a Break!"
        content.body = """
        You've been working for \(sessionMinutes) minutes.
        Taking regular breaks helps maintain productivity and well-being.
        """
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "BREAK_REMINDER"
        
        // Action buttons
        let startBreakAction = UNNotificationAction(
            identifier: "START_BREAK",
            title: "⏸ Take Break (15m)",
            options: []
        )
        
        let keepWorkingAction = UNNotificationAction(
            identifier: "KEEP_WORKING",
            title: "🔥 Keep Working",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_BREAK",
            title: "😴 Snooze (5m)",
            options: []
        )
        
        let showStatsAction = UNNotificationAction(
            identifier: "SHOW_STATS",
            title: "📊 Show Stats",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "BREAK_REMINDER",
            actions: [startBreakAction, keepWorkingAction, snoozeAction, showStatsAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: nil // Show immediately
        )
        
        delegate?.breakReminderManager(self, needsNotification: request)
        delegate?.breakReminderManager(self, didSendBreakNotification: sessionDuration)
    }
    
    /// Start a break
    func startBreak() {
        guard !isCurrentlyOnBreak else {
            logger.warning("Break already in progress")
            return
        }
        
        isCurrentlyOnBreak = true
        breakStartTime = Date()
        logger.info("☕ Break started")
        
        // End current continuous session in UsageTrackingManager
        UsageTrackingManager.shared.endContinuousSession()
        
        delegate?.breakReminderManager(self, didStartBreak: 0) // Duration will be calculated when break ends
    }
    
    /// End current break
    func endBreak() {
        guard isCurrentlyOnBreak, let breakStart = breakStartTime else {
            logger.warning("No active break to end")
            return
        }
        
        let breakDuration = Date().timeIntervalSince(breakStart)
        totalBreakTime += breakDuration
        
        // Record the break
        breaksTaken.append(SessionRecord(start: breakStart, duration: breakDuration))
        
        isCurrentlyOnBreak = false
        breakStartTime = nil
        
        let minutes = Int(breakDuration / 60)
        logger.info("🔄 Break ended after \(minutes) minutes")
        
        delegate?.breakReminderManager(self, didEndBreak: breakDuration)
    }
    
    // MARK: - Break Timer (Scheduled Breaks)
    
    /// Start break timer with specified duration
    func startBreakTimer(duration: TimeInterval = 900) { // Default 15 minutes
        logger.info("⏲ Starting break timer for \(Int(duration/60)) minutes")
        
        breakTimer?.invalidate() // Stop any existing timer
        breakTimerStartTime = Date()
        
        breakTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.handleBreakTimerExpired()
        }
    }
    
    /// Stop break timer
    func stopBreakTimer() {
        breakTimer?.invalidate()
        breakTimer = nil
        breakTimerStartTime = nil
        logger.info("⏹ Break timer stopped")
    }
    
    /// Check if break timer is active
    var isBreakTimerActive: Bool {
        return breakTimer != nil && breakTimerStartTime != nil
    }
    
    /// Get remaining break timer time
    func getBreakTimerRemaining() -> TimeInterval {
        guard let startTime = breakTimerStartTime, isBreakTimerActive else { return 0 }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let totalDuration: TimeInterval = 900 // Default 15 minutes, should be configurable
        return max(0, totalDuration - elapsed)
    }
    
    private func handleBreakTimerExpired() {
        logger.info("⏰ Break timer expired")
        breakTimerStartTime = nil
        
        // Send notification that break time is over
        let content = UNMutableNotificationContent()
        content.title = "🔔 Break Time Over"
        content.body = "Your break time has ended. Ready to get back to work?"
        content.sound = UNNotificationSound.default
        
        let backToWorkAction = UNNotificationAction(
            identifier: "BACK_TO_WORK",
            title: "💪 Back to Work",
            options: []
        )
        
        let extendBreakAction = UNNotificationAction(
            identifier: "EXTEND_BREAK",
            title: "⏰ Extend Break (5m)",
            options: []
        )
        
        let showDashboardAction = UNNotificationAction(
            identifier: "SHOW_DASHBOARD",
            title: "📊 Show Dashboard",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "BREAK_TIMER_EXPIRED",
            actions: [backToWorkAction, extendBreakAction, showDashboardAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "break-timer-expired-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        delegate?.breakReminderManager(self, needsNotification: request)
    }
    
    // MARK: - Sticky Break Notifications
    
    /// Start sticky break reminders (persistent notifications)
    func startStickyBreakReminders() {
        guard stickyRemindersEnabled else {
            logger.info("🔇 Sticky reminders disabled")
            return
        }
        
        logger.info("🔄 Starting sticky break reminders")
        
        stickyBreakStartTime = Date()
        
        // Send initial notification
        sendBreakNotification(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration(),
                              overrideIdentifier: stickyBreakNotificationID)
        
        stickyBreakTimer = Timer.scheduledTimer(withTimeInterval: stickyRepeatInterval,
                                               repeats: true) { [weak self] timer in
            guard let self = self, let start = self.stickyBreakStartTime else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > self.stickyMaxDuration {
                self.stopStickyBreakReminders()
                return
            }
            
            self.sendBreakNotification(sessionDuration: UsageTrackingManager.shared.getCurrentSessionDuration(),
                                       overrideIdentifier: self.stickyBreakNotificationID)
        }
    }
    
    /// Stop sticky break reminders
    func stopStickyBreakReminders() {
        logger.info("⏹ Stopping sticky break reminders")
        
        stickyBreakTimer?.invalidate()
        stickyBreakTimer = nil
        stickyBreakStartTime = nil
        
        // Remove delivered and pending notifications
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [stickyBreakNotificationID])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [stickyBreakNotificationID])
    }
    
    /// Toggle sticky reminders on/off
    func toggleStickyReminders() -> Bool {
        self.stickyRemindersEnabled.toggle()
        let status = self.stickyRemindersEnabled ? "ON" : "OFF"
        logger.info("🔔 Sticky reminders: \(status)")
        
        if !self.stickyRemindersEnabled {
            self.stopStickyBreakReminders()
        }
        
        return self.stickyRemindersEnabled
    }
    
    // MARK: - Analytics
    
    /// Generate break analytics summary
    func generateBreakAnalytics() -> (
        totalBreakTime: TimeInterval,
        breakCount: Int,
        averageBreakTime: TimeInterval,
        longestBreak: TimeInterval,
        isCurrentlyOnBreak: Bool,
        currentBreakDuration: TimeInterval?
    ) {
        let breakCount = breaksTaken.count
        let averageBreakTime = breakCount > 0 ? totalBreakTime / Double(breakCount) : 0
        let longestBreak = breaksTaken.map { $0.duration }.max() ?? 0
        
        var currentBreakDuration: TimeInterval?
        if let breakStart = breakStartTime {
            currentBreakDuration = Date().timeIntervalSince(breakStart)
        }
        
        return (
            totalBreakTime: getTotalBreakTime(),
            breakCount: breakCount,
            averageBreakTime: averageBreakTime,
            longestBreak: longestBreak,
            isCurrentlyOnBreak: isCurrentlyOnBreak,
            currentBreakDuration: currentBreakDuration
        )
    }
}
