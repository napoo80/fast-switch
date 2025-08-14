# FastSwitch

FastSwitch is a lightweight macOS menu-bar app that lets you switch to your favorite apps instantly with F1/F2/F3 keys (or more).

## Features

* Runs entirely in the background — menu bar icon only, no Dock icon or ⌘-Tab entry.
* Single-tap F-keys to bring Chrome, Terminal, and VS Code to the front (launches if closed).
* Fully customizable — map any F-key to any app in `AppDelegate.swift`.

## Requirements

* macOS 11.0 or later
* Xcode 14 or later
* **System Settings → Keyboard →** “Use F1, F2, etc. keys as standard function keys” enabled for bare F-keys.

## Build Instructions (Development / Debug)

1. **Clone the repo:**

   ```bash
   git clone https://github.com/yourusername/FastSwitch.git
   cd FastSwitch
   ```
2. **Open in Xcode:**

   ```bash
   open FastSwitch/FastSwitch.xcodeproj
   ```
3. In the target's **Info** tab, ensure:

   * `Application is agent (UIElement)` = `YES` (Boolean) — hides the Dock icon.
4. In Xcode:

   * Go to **Product → Scheme → Edit Scheme…**
   * Under **Run**, set **Build Configuration** to `Debug`.
5. Build & run (**⌘R**) to test locally.

## Installing on Another Mac (Debug Build)

1. Build in **Debug** mode.
2. In Xcode: **Product → Show Build Folder in Finder**.
3. Navigate to `Build/Products/Debug/` and copy `FastSwitch.app` to `/Applications` or `~/Applications` on the other Mac.
4. On first launch, macOS will warn it’s from an unidentified developer:

   * Go to **System Settings → Privacy & Security → Open Anyway**.
   * Approve and relaunch.
5. Add to Login Items:

   * **System Settings → General → Login Items → +** → select `FastSwitch.app`.

## Customizing Hotkeys

* Edit the `mapping` dictionary in `AppDelegate.swift`. Example:

  ```swift
  private let mapping: [UInt32: String] = [
      UInt32(kVK_F1): "com.google.Chrome",
      UInt32(kVK_F2): "com.apple.Terminal",
      UInt32(kVK_F3): "com.microsoft.VSCode"
  ]
  ```
* Find an app’s bundle ID:

  ```bash
  osascript -e 'id of app "App Name"'
  ```
* Rebuild after making changes.

## Usage Analytics & Reports

FastSwitch includes comprehensive usage tracking and reporting features:

### 📊 Built-in Reports
- **Daily Dashboard**: Automatic daily summary with app usage breakdown
- **Weekly Reports**: 7-day productivity analysis
- **Yearly Reports**: Annual trends and statistics
- **Real-time Tracking**: Session time, breaks, Deep Focus sessions

### 💾 Data Export & Analysis
For advanced analysis, you can export your usage data:

1. **Export Data**: Menu → `📊 Reportes` → `💾 Exportar Datos`
2. **External Analysis**: Use the included Python analyzer for detailed insights

```bash
python3 usage_analyzer.py FastSwitch-Usage-Data-2024-08-14.json
```

**📋 Full documentation**: See [USAGE_ANALYZER.md](USAGE_ANALYZER.md) for complete setup and usage instructions.

## Reset permissions

tccutil reset Accessibility Bandonea.FastSwitch
tccutil reset AppleEvents Bandonea.FastSwitch    

## License

MIT

---
