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

 


## 🧹 Limpieza Completa de FastSwitch

1. Cerrar la app:
pkill -f FastSwitch

1. Borrar todos los datos persistentes:
# UserDefaults
defaults delete Bandonea.FastSwitch 2>/dev/null || true
tccutil reset Accessibility Bandonea.FastSwitch
tccutil reset AppleEvents Bandonea.FastSwitch   

# Borrar claves específicas que usa la app
defaults delete Bandonea.FastSwitch FastSwitchUsageHistory 2>/dev/null || true
defaults delete Bandonea.FastSwitch MateReductionPlan 2>/dev/null || true

3. Limpiar notificaciones pendientes:
- Ve a System Preferences → Notifications & Focus
- Busca "FastSwitch" y bórralo de la lista si aparece

4. Resetear permisos de Accessibility y Automation:
- Ve a System Preferences → Security & Privacy → Privacy
- En Accessibility: quita FastSwitch si está listado
- En Automation: quita FastSwitch si está listado

5. Borrar archivos temporales:
cd /Users/gaston/code/repos/fast-switch
rm -f phrases.json.backup 2>/dev/null || true
rm -f *.log 2>/dev/null || true

6. Clean build en Xcode:
- Product → Clean Build Folder (⇧⌘K)

7. Rebuild y test:
cd FastSwitch
xcodebuild -scheme FastSwitch -configuration Debug clean build

Una vez hecho esto, al ejecutar la app por primera vez:
1. Te va a pedir permisos de notificaciones
2. Te va a pedir Accessibility
3. Va a inicializar el plan de mate desde cero (empezando hoy con 5 termos)
4. Va a cargar las frases motivacionales desde phrases.json


## License

MIT

---


### Reset 

tccutil reset Accessibility com.bandonea.FastSwitch
tccutil reset AppleEvents   com.bandonea.FastSwitch