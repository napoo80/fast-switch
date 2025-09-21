//
//  UsageTrackingManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import ApplicationServices
import AppKit
import os.log

// MARK: - UsageTrackingManager Protocol

protocol UsageTrackingManagerDelegate: AnyObject {
    func usageTrackingManager(_ manager: UsageTrackingManager, didUpdateSessionDuration duration: TimeInterval)
    func usageTrackingManager(_ manager: UsageTrackingManager, didDetectActivity: Bool)
    func usageTrackingManager(_ manager: UsageTrackingManager, didUpdateAppUsage appUsage: [String: TimeInterval])
    func usageTrackingManager(_ manager: UsageTrackingManager, didDetectCallStatus inCall: Bool)
}

// MARK: - UsageTrackingManager

final class UsageTrackingManager: NSObject {
    
    // MARK: - Singleton
    static let shared = UsageTrackingManager()
    
    // MARK: - Properties
    weak var delegate: UsageTrackingManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "UsageTrackingManager")
    
    // Session tracking
    private var usageTimer: Timer?
    private var sessionStartTime: Date?
    private var totalActiveTime: TimeInterval = 0
    private var lastActivityTime: Date = Date()
    private var currentFrontApp: String?
    private var lastAppCheckTime: Date = Date()
    
    // App usage tracking
    private var appUsageToday: [String: TimeInterval] = [:]
    
    // Continuous work session tracking
    private var currentContinuousSessionStart: Date?
    private var continuousWorkSessions: [SessionRecord] = []
    private var longestContinuousSession: TimeInterval = 0
    
    // Call detection
    private var isInCall: Bool = false
    private var currentDayCallTime: TimeInterval = 0
    private var callStartTime: Date?
    
    // Configuration
    private let checkInterval: TimeInterval = 1.0  // Check every second
    private let idleThreshold: TimeInterval = 30.0  // 30 seconds of inactivity
    private let callIdleThreshold: TimeInterval = 120.0  // 2 minutes during calls
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        logger.info("📊 UsageTrackingManager initialized")
    }
    
    // MARK: - Public API
    
    /// Start usage tracking
    func startTracking() {
        guard usageTimer == nil else {
            logger.warning("Usage tracking already started")
            return
        }
        
        sessionStartTime = Date()
        lastActivityTime = Date()
        currentFrontApp = getCurrentFrontApp()
        lastAppCheckTime = Date()
        currentContinuousSessionStart = Date()
        
        logger.info("🏁 Starting usage tracking session")
        
        usageTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkActivity()
        }
    }
    
    /// Stop usage tracking
    func stopTracking() {
        usageTimer?.invalidate()
        usageTimer = nil
        
        // End current continuous session
        if let sessionStart = currentContinuousSessionStart {
            let duration = Date().timeIntervalSince(sessionStart)
            continuousWorkSessions.append(SessionRecord(start: sessionStart, duration: duration))
            if duration > longestContinuousSession {
                longestContinuousSession = duration
            }
            currentContinuousSessionStart = nil
        }
        
        logger.info("⏹️ Stopped usage tracking session")
    }
    
    /// Get current session duration
    func getCurrentSessionDuration() -> TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    /// Get current continuous work session duration
    func getCurrentContinuousSessionDuration() -> TimeInterval {
        guard let sessionStart = currentContinuousSessionStart else { return 0 }
        return Date().timeIntervalSince(sessionStart)
    }
    
    /// Reset session tracking
    func resetSession() {
        sessionStartTime = Date()
        totalActiveTime = 0
        appUsageToday.removeAll()
        continuousWorkSessions.removeAll()
        longestContinuousSession = 0
        currentContinuousSessionStart = Date()
        
        logger.info("🔄 Reset usage tracking session")
    }
    
    /// Manually toggle call status
    func toggleCallStatus() -> Bool {
        isInCall.toggle()
        
        if isInCall {
            callStartTime = Date()
            logger.info("📞 Manual call started")
        } else {
            if let callStart = callStartTime {
                currentDayCallTime += Date().timeIntervalSince(callStart)
                logger.info("📞 Manual call ended, duration: \(Date().timeIntervalSince(callStart))s")
            }
            callStartTime = nil
        }
        
        delegate?.usageTrackingManager(self, didDetectCallStatus: isInCall)
        return isInCall
    }
    
    /// Get current app usage for today
    func getAppUsageToday() -> [String: TimeInterval] {
        return appUsageToday
    }
    
    /// Get continuous work sessions
    func getContinuousWorkSessions() -> [SessionRecord] {
        return continuousWorkSessions
    }
    
    /// Get longest continuous session
    func getLongestContinuousSession() -> TimeInterval {
        return longestContinuousSession
    }
    
    /// Get total call time for today
    func getCurrentDayCallTime() -> TimeInterval {
        var totalTime = currentDayCallTime
        
        // Add current call time if in call
        if let callStart = callStartTime {
            totalTime += Date().timeIntervalSince(callStart)
        }
        
        return totalTime
    }
    
    /// Check if currently in a call
    func isCurrentlyInCall() -> Bool {
        return isInCall
    }
    
    // MARK: - Private Methods
    
    private func checkActivity() {
        let currentTime = Date()
        let timeSinceLastActivity = currentTime.timeIntervalSince(lastActivityTime)
        let effectiveIdleThreshold = isInCall ? callIdleThreshold : idleThreshold
        let isActive = timeSinceLastActivity < effectiveIdleThreshold
        
        // Detect call status automatically
        detectCallStatus()
        
        // Track app usage
        trackAppUsage()
        
        if isActive {
            // Check for mouse/keyboard activity
            if CGEventSource(stateID: .hidSystemState) != nil {
                let secondsSinceLastEvent = CGEventSource.secondsSinceLastEventType(
                    .hidSystemState,
                    eventType: .mouseMoved
                )
                
                let keyboardSeconds = CGEventSource.secondsSinceLastEventType(
                    .hidSystemState,
                    eventType: .keyDown
                )
                
                let actualSecondsSinceActivity = min(Double(secondsSinceLastEvent), Double(keyboardSeconds))
                
                if actualSecondsSinceActivity < effectiveIdleThreshold {
                    lastActivityTime = currentTime
                }
            }
        }
        
        // Notify delegate about session duration updates
        let sessionDuration = getCurrentSessionDuration()
        delegate?.usageTrackingManager(self, didUpdateSessionDuration: sessionDuration)
        delegate?.usageTrackingManager(self, didDetectActivity: isActive)
    }
    
    private func trackAppUsage() {
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastAppCheckTime)
        
        if let currentApp = getCurrentFrontApp() {
            appUsageToday[currentApp, default: 0] += timeElapsed
            currentFrontApp = currentApp
        }
        
        lastAppCheckTime = now
        
        // Notify delegate about app usage updates
        delegate?.usageTrackingManager(self, didUpdateAppUsage: appUsageToday)
    }
    
    private func getCurrentFrontApp() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return frontApp.bundleIdentifier ?? frontApp.localizedName ?? "Unknown"
    }
    
    private func detectCallStatus() {
        // List of apps that indicate video calls
        let callApps = [
            "com.google.Chrome",
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.tinyspeck.slackmacgap",
            "com.apple.FaceTime",
            "com.skype.skype",
            "com.cisco.webexmeetingsapp"
        ]
        
        var detectedApps: [String] = []
        
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            if callApps.contains(bundleID) && AppSwitchingManager.shared.isAppRunning(bundleID: bundleID) {
                detectedApps.append(bundleID)
                if bundleID == "com.google.Chrome" {
                    // Check if Chrome has a Meet tab (simplified detection)
                    // In a real implementation, you might use AppleScript to check tab titles
                }
            }
        }
        
        let wasInCall = isInCall
        isInCall = !detectedApps.isEmpty
        
        // Handle call state transitions
        if isInCall && !wasInCall {
            // Call started
            callStartTime = Date()
            logger.info("📞 Detected call started with apps: \(detectedApps)")
        } else if !isInCall && wasInCall {
            // Call ended
            if let callStart = callStartTime {
                currentDayCallTime += Date().timeIntervalSince(callStart)
                logger.info("📞 Detected call ended, duration: \(Date().timeIntervalSince(callStart))s")
            }
            callStartTime = nil
        }
        
        if isInCall != wasInCall {
            delegate?.usageTrackingManager(self, didDetectCallStatus: isInCall)
        }
    }
    
    /// End current continuous session and start a new one
    func endContinuousSession() {
        if let sessionStart = currentContinuousSessionStart {
            let duration = Date().timeIntervalSince(sessionStart)
            continuousWorkSessions.append(SessionRecord(start: sessionStart, duration: duration))
            if duration > longestContinuousSession {
                longestContinuousSession = duration
            }
            logger.info("📊 Ended continuous session: \(duration)s")
        }
        
        // Start new session
        currentContinuousSessionStart = Date()
        logger.info("🆕 Started new continuous session")
    }
    
    /// Generate usage analytics summary
    func generateUsageAnalytics() -> (
        totalSession: TimeInterval,
        totalAppUsage: TimeInterval,
        mostUsedApp: String?,
        continuousSessions: Int,
        longestSession: TimeInterval,
        callTime: TimeInterval
    ) {
        let totalSession = getCurrentSessionDuration()
        let totalAppUsage = appUsageToday.values.reduce(0, +)
        let mostUsedApp = appUsageToday.max(by: { $0.value < $1.value })?.key
        let callTime = getCurrentDayCallTime()
        
        return (
            totalSession: totalSession,
            totalAppUsage: totalAppUsage,
            mostUsedApp: mostUsedApp,
            continuousSessions: continuousWorkSessions.count,
            longestSession: longestContinuousSession,
            callTime: callTime
        )
    }
}
