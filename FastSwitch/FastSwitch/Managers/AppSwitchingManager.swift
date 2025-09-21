//
//  AppSwitchingManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import Cocoa
import os.log

// MARK: - AppSwitchingManager Protocol

protocol AppSwitchingManagerDelegate: AnyObject {
    func appSwitchingManager(_ manager: AppSwitchingManager, needsAppleScript script: String)
    func appSwitchingManager(_ manager: AppSwitchingManager, needsSpotifyAction action: String)
}

// MARK: - AppSwitchingManager

final class AppSwitchingManager: NSObject {
    
    // MARK: - Singleton
    static let shared = AppSwitchingManager()
    
    // MARK: - Properties  
    weak var delegate: AppSwitchingManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "AppSwitchingManager")
    
    // Action delay for double-tap sequences
    private let actionDelay: TimeInterval = 0.12
    
    // MARK: - Public API
    
    /// Activate an application by bundle ID
    func activateApp(bundleID: String, completion: (() -> Void)? = nil) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.warning("No application found for bundle ID: \(bundleID)")
            return
        }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, error in
            if let error = error {
                self?.logger.error("Failed to activate app \(bundleID): \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully activated app: \(bundleID)")
            }
            
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + (self?.actionDelay ?? 0.12)) {
                    completion()
                }
            }
        }
    }
    
    /// Activate app and trigger in-app action (for double-tap)
    func activateAppWithAction(bundleID: String, completion: (() -> Void)? = nil) {
        activateApp(bundleID: bundleID) { [weak self] in
            self?.triggerInAppAction(for: bundleID)
            completion?()
        }
    }
    
    /// Check if an app is currently running
    func isAppRunning(bundleID: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
    
    /// Pre-open an app without activating it (for automation permissions)
    func preopenIfNeeded(bundleID: String) {
        guard !isAppRunning(bundleID: bundleID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            if let error = error {
                self?.logger.error("Failed to pre-open app \(bundleID): \(error.localizedDescription)")
            } else {
                self?.logger.info("Pre-opened app for permissions: \(bundleID)")
            }
        }
    }
    
    /// Open URL in default browser/app
    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
        logger.info("Opened URL: \(url.absoluteString)")
    }
    
    // MARK: - In-App Actions
    
    private func triggerInAppAction(for bundleID: String) {
        logger.info("🔥 Triggering in-app action for bundleID: \(bundleID)")
        
        switch bundleID {
        case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92":
            // F2/F3 double → Ctrl+W (Window Switcher for VSCode/Cursor)
            logger.info("⌨️ Sending Ctrl+W for VSCode/Cursor")
            sendShortcut(letter: "w", control: true)
            
        case "com.google.Chrome", "com.apple.finder", "com.apple.Terminal", "com.mitchellh.ghostty":
            logger.info("⌨️ Sending ⌘T for \(bundleID)")
            sendShortcut(letter: "t", command: true)
            
        case "com.spotify.client":
            logger.info("🎵 Sending play/pause for Spotify")
            delegate?.appSwitchingManager(self, needsSpotifyAction: "playPause")
            
        case "com.apple.TextEdit":
            logger.info("⌨️ Sending ⌘N for TextEdit")
            sendShortcut(letter: "n", command: true)
            
        case "notion.id", "com.notion.Notion":
            logger.info("⌨️ Sending ⌘N for Notion")
            sendShortcut(letter: "n", command: true)
            
        default:
            logger.warning("❌ No in-app action configured for bundleID: \(bundleID)")
        }
    }
    
    // MARK: - Keyboard Shortcuts
    
    private func sendShortcut(
        letter: String,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        var mods: [String] = []
        if command { mods.append("command down") }
        if shift   { mods.append("shift down") }
        if option  { mods.append("option down") }
        if control { mods.append("control down") }
        
        let usingPart = mods.isEmpty ? "" : " using {\(mods.joined(separator: ", "))}"
        let script = """
        tell application id "com.apple.systemevents"
            keystroke "\(letter)"\(usingPart)
        end tell
        """
        
        delegate?.appSwitchingManager(self, needsAppleScript: script)
    }
    
    /// Get user-friendly display name for an app bundle ID
    func getAppDisplayName(from identifier: String) -> String {
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
}
