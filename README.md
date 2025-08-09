# FastSwitch

FastSwitch is a lightweight macOS menu-bar app that lets you switch to your favorite apps instantly with F1/F2/F3 keys (or more).

## Features
- Runs in the background (menu bar only, no Dock icon).
- Press F1/F2/F3 to bring Chrome, Terminal, and VS Code to the front.
- Easily customizable: map any F-key to any app by editing `AppDelegate.swift`.

## Requirements
- macOS 11.0 or later
- Xcode 14 or later

## Build Instructions
1. Clone the repo.
2. Open `FastSwitch.xcodeproj` in Xcode.
3. In the target's **Info** tab, ensure `Application is agent (UIElement)` is set to `YES`.
4. Build & run.

## Customizing Hotkeys
- Edit the `mapping` dictionary in `AppDelegate.swift`.
- Use `osascript -e 'id of app "App Name"'` to find an app’s bundle ID.
- Rebuild the app after making changes.

## Adding to Login Items
- Move the built `.app` to `/Applications` or `~/Applications`.
- Go to **System Settings → General → Login Items**, add the app.

## License
MIT


