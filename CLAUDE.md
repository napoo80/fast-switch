# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FastSwitch is a macOS menu bar application that provides instant app switching using F-keys. It's built with SwiftUI and uses Carbon for global hotkey registration and AppleScript for automation.

## Build Commands

**Development/Debug Build:**
```bash
# Open in Xcode
open FastSwitch/FastSwitch.xcodeproj

# Build and run in Xcode: ⌘R
# Or use xcodebuild:
cd FastSwitch
xcodebuild -scheme FastSwitch -configuration Debug build
```

**Testing:**
```bash
cd FastSwitch
xcodebuild test -scheme FastSwitch -destination 'platform=macOS'
```

## Architecture

### Core Components

- **FastSwitchApp.swift**: SwiftUI app entry point with minimal UI (Settings with EmptyView)
- **AppDelegate.swift**: Main application logic containing:
  - Carbon hotkey registration system
  - F-key to app bundle ID mapping configuration
  - Double-tap detection for in-app actions
  - AppleScript automation for app interactions
  - Computer usage tracking and break notifications

### Key Architecture Patterns

1. **Menu Bar Only App**: Uses `NSApp.setActivationPolicy(.accessory)` to hide from Dock and app switcher
2. **Global Hotkeys**: Carbon Event Manager for system-wide F-key capture
3. **App Activation**: NSWorkspace for launching/focusing apps by bundle ID
4. **Automation**: AppleScript via NSAppleScript for sending keystrokes and app control
5. **Usage Tracking**: CGEventSource API for activity detection and Timer-based session management

### Configuration

App mappings are defined in `AppDelegate.swift` in the `mapping` dictionary:
```swift
private let mapping: [UInt32: String] = [
    UInt32(kVK_F1): "com.google.Chrome",
    UInt32(kVK_F2): "com.microsoft.VSCode",
    // ... etc
]
```

### Double-Tap Actions

- Single tap: Activates/launches the app
- Double tap (within 0.45s): Activates app + sends specific keystroke
- Examples: F2 double-tap → VSCode + ⌘Esc (Claude Code), Chrome double-tap → ⌘T

### Special Actions

Some F-keys trigger custom actions instead of apps:
- `action:meet-mic` (F5): Google Meet microphone toggle (⌘D)
- `action:meet-cam` (F6): Google Meet camera toggle (⌘E)
- `action:insta360-track` (F7): Insta360 Link Controller AI tracking (⌥T)

### Usage Tracking Feature

- **Session Tracking**: Monitors computer usage time using CGEventSource API
- **Call Detection**: Automatically detects video calls (Meet, Zoom, Teams) and adjusts idle thresholds
- **Smart Notifications**: Context-aware break reminders with different behavior during calls
- **Manual Controls**: Menu bar toggle for call status and session reset
- **Configurable Intervals**: 45min, 60min, or 90min notification intervals

### Permissions Required

- **Accessibility**: For global hotkey registration and keystroke automation
- **Automation**: For controlling specific apps (Chrome, Spotify, System Events)
- **Notifications**: For break reminder notifications

## Development Notes

- Bundle IDs can be found with: `osascript -e 'id of app "App Name"'`
- Rebuild required after modifying the mapping dictionary
- The app uses Spanish strings in some UI elements ("Solicitar permisos…", "Salir")
- Error handling includes automatic permission prompts for Accessibility/Automation