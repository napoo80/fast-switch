//
//  HotkeyManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import Carbon.HIToolbox
import os.log

// MARK: - HotkeyManager Protocols

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManager(_ manager: HotkeyManager, didReceiveAction action: String)
    func hotkeyManager(_ manager: HotkeyManager, didReceiveDoubleAction action: String, completion: (() -> Void)?)
}

// MARK: - HotkeyManager

final class HotkeyManager: NSObject {
    
    // MARK: - Singleton
    static let shared = HotkeyManager()
    
    // MARK: - Properties
    weak var delegate: HotkeyManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "HotkeyManager")
    
    // Hotkey registration
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []
    
    // Double-tap detection
    private var lastKeyCode: UInt32?
    private var lastPressDate: Date?
    private let doubleTapWindow: TimeInterval = 0.45
    
    // Key mapping: F-key codes to bundle IDs or actions
    private let mapping: [UInt32: String] = [
        UInt32(kVK_F1):  "com.google.Chrome",
        UInt32(kVK_F2):  "com.microsoft.VSCode",            // 1 tap: VSCode, 2 taps: Ctrl+W (Window Switcher)
        UInt32(kVK_F3):  "com.todesktop.230313mzl4w4u92",   // 1 tap: Cursor, 2 taps: Ctrl+W (Window Switcher)
        UInt32(kVK_F4):  "com.apple.finder",
        
        UInt32(kVK_F5):  "action:dasung-refresh",
        UInt32(kVK_F6):  "action:paperlike-resolution",
        UInt32(kVK_F7):  "action:paperlike-optimize",
        
        UInt32(kVK_F8):  "com.tinyspeck.slackmacgap",
        UInt32(kVK_F19): "notion.id",
        UInt32(kVK_F10): "com.apple.TextEdit",
        UInt32(kVK_F11): "com.apple.Terminal",
        UInt32(kVK_F12): "com.mitchellh.ghostty"
    ]
    
    // MARK: - Initialization
    private override init() {
        super.init()
        setupHotkeyHandler()
    }
    
    deinit {
        unregisterHotkeys()
    }
    
    // MARK: - Setup
    private func setupHotkeyHandler() {
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &hotKeyEventSpec, userData, &eventHandlerRef)
    }
    
    // MARK: - Public API
    func registerHotkeys() {
        unregisterHotkeys()
        logger.info("Registering hotkeys...")
        
        for (keyCode, target) in mapping {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x484B5953), id: keyCode) // 'HKYS'
            let result = RegisterEventHotKey(keyCode, 0, id, GetApplicationEventTarget(), 0, &ref)
            hotKeys.append(ref)
            
            let fKeyNumber = getFKeyNumber(for: keyCode)
            logger.info("F\(fKeyNumber) (code: \(keyCode)) → \(target) [result: \(result)]")
        }
        
        logger.info("✅ \(self.hotKeys.count) hotkeys registered")
    }
    
    func unregisterHotkeys() {
        for hk in hotKeys {
            if let hk = hk {
                UnregisterEventHotKey(hk)
            }
        }
        hotKeys.removeAll()
        logger.info("Unregistered all hotkeys")
    }
    
    // MARK: - Hotkey Handling
    fileprivate func handleHotKey(keyCode: UInt32) {
        guard let target = mapping[keyCode] else {
            logger.warning("No mapping found for keyCode: \(keyCode)")
            return
        }
        
        let now = Date()
        let timeSinceLastPress = lastPressDate != nil ? now.timeIntervalSince(lastPressDate!) : 999.0
        let isDoubleTap = (lastKeyCode == keyCode) && (lastPressDate != nil) && (timeSinceLastPress < doubleTapWindow)
        
        logger.info("Key F\(self.getFKeyNumber(for: keyCode)) pressed (code: \(keyCode)) → \(target)")
        logger.debug("Last key: \(self.lastKeyCode ?? 0), Time since last: \(String(format: "%.3f", timeSinceLastPress))s")
        logger.debug("Double tap window: \(self.doubleTapWindow)s, Is double tap: \(isDoubleTap)")
        
        lastKeyCode = keyCode
        lastPressDate = now
        
        if target.hasPrefix("action:") {
            logger.info("Executing action: \(target)")
            delegate?.hotkeyManager(self, didReceiveAction: target)
            return
        }
        
        if isDoubleTap {
            logger.info("👆👆 DOUBLE TAP detected - activating app + in-app action")
            delegate?.hotkeyManager(self, didReceiveDoubleAction: target) { [weak self] in
                self?.logger.info("📱 App activated, triggering in-app action for \(target)")
            }
        } else {
            logger.info("👆 SINGLE TAP - activating app only")
            delegate?.hotkeyManager(self, didReceiveAction: target)
        }
    }
    
    // MARK: - Helper Methods
    private func getFKeyNumber(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_F1): return "1"
        case UInt32(kVK_F2): return "2"
        case UInt32(kVK_F3): return "3"
        case UInt32(kVK_F4): return "4"
        case UInt32(kVK_F5): return "5"
        case UInt32(kVK_F6): return "6"
        case UInt32(kVK_F7): return "7"
        case UInt32(kVK_F8): return "8"
        case UInt32(kVK_F9): return "9"
        case UInt32(kVK_F10): return "10"
        case UInt32(kVK_F11): return "11"
        case UInt32(kVK_F12): return "12"
        case UInt32(kVK_F19): return "19"
        default: return "?\(keyCode)"
        }
    }
}

// MARK: - Carbon Event Handler

private var hotKeyEventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

private func hotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    
    var hkID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    
    guard status == noErr else { return status }
    
    let keyCode = hkID.id
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKey(keyCode: keyCode)
    
    return noErr
}