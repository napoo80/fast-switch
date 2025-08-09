import Cocoa
import Carbon.HIToolbox

// Callback global para hotkeys (Carbon)
private func hotKeyHandler(nextHandler: EventHandlerCallRef?,
                           event: EventRef?,
                           userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hkID = EventHotKeyID()
    GetEventParameter(event,
                      EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID),
                      nil,
                      MemoryLayout<EventHotKeyID>.size,
                      nil,
                      &hkID)
    let keyCode = hkID.id
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.handleHotKey(keyCode: keyCode)
    return noErr
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []

    // Doble pulsación
    private var lastKeyCode: UInt32?
    private var lastPressDate: Date?
    private let doubleTapWindow: TimeInterval = 1.2   // s
    private let actionDelay: TimeInterval = 0.25      // s para asegurar app al frente

    // Mapeo F-key -> bundle ID (verifica Cursor/Notion en tu Mac)
    private let mapping: [UInt32: String] = [
        UInt32(kVK_F1):  "com.google.Chrome",                // Chrome
        UInt32(kVK_F2):  "com.microsoft.VSCode",             // VS Code
        UInt32(kVK_F3):  "com.todesktop.230313mzl4w4u92",    // Cursor (puede variar)
        UInt32(kVK_F4):  "com.apple.finder",                 // Finder
        UInt32(kVK_F8):  "com.spotify.client",               // Spotify
        UInt32(kVK_F10): "notion.id",                        // Notion (o com.notion.Notion)
        UInt32(kVK_F11): "com.apple.TextEdit",               // TextEdit
        UInt32(kVK_F12): "com.apple.Terminal"                // Terminal
    ]

    // Etiquetas bonitas para logs
    private let fLabels: [UInt32: String] = [
        UInt32(kVK_F1): "F1",  UInt32(kVK_F2): "F2",  UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",  UInt32(kVK_F5): "F5",  UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",  UInt32(kVK_F8): "F8",  UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",UInt32(kVK_F11): "F11",UInt32(kVK_F12): "F12"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menú en barra
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "F→"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Solicitar permisos…", action: #selector(requestAutomationPrompts), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // Handler de hotkeys
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyHandler,
                            1,
                            &eventType,
                            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                            &eventHandlerRef)

        registerHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) { unregisterHotkeys() }

    // Registro de hotkeys globales
    private func registerHotkeys() {
        unregisterHotkeys()
        for (keyCode, _) in mapping {
            var ref: EventHotKeyRef?
            var id = EventHotKeyID(signature: OSType(0x484B5953), id: keyCode) // 'HKYS'
            RegisterEventHotKey(keyCode, 0, id, GetApplicationEventTarget(), 0, &ref)
            hotKeys.append(ref)
        }
    }
    private func unregisterHotkeys() {
        for hk in hotKeys { if let hk { UnregisterEventHotKey(hk) } }
        hotKeys.removeAll()
    }

    // MARK: - Handler principal
    fileprivate func handleHotKey(keyCode: UInt32) {
        guard let bundleID = mapping[keyCode] else { return }
        let label = fLabels[keyCode] ?? "F?"

        let now = Date()
        let isDoubleTap = (lastKeyCode == keyCode) && (lastPressDate != nil)
                        && (now.timeIntervalSince(lastPressDate!) < doubleTapWindow)
        lastKeyCode = keyCode
        lastPressDate = now

        let activeBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        print("Tecla: \(label), Activa: \(activeBundle) doubleTap: \(isDoubleTap)")

        if isDoubleTap {
            activateApp(bundleID: bundleID) { [weak self] in
                self?.triggerInAppAction(for: bundleID)
            }
        } else {
            activateApp(bundleID: bundleID, completion: nil)
        }
    }

    // Activar/Lanzar app y luego ejecutar (opcionalmente) una acción
    private func activateApp(bundleID: String, completion: (() -> Void)?) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            if let completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + self.actionDelay) { completion() }
            }
        }
    }

    // Acciones internas tras doble pulsación
    private func triggerInAppAction(for bundleID: String) {
        switch bundleID {
        case "com.google.Chrome":
            sendKey(.t, flags: [.maskCommand])          // ⌘T (nueva pestaña)
        case "com.apple.finder":
            sendKey(.t, flags: [.maskCommand])          // ⌘T (nueva pestaña)
        case "com.apple.Terminal":
            sendKey(.t, flags: [.maskCommand])          // ⌘T (nueva pestaña)
        case "com.spotify.client":
            playPauseSpotifyWithRetry()                 // play/pause con reintento
        default:
            break
        }
    }

    // MARK: - Menú: solicitar permisos de Automatización
    @objc private func requestAutomationPrompts() {
        // Abrimos las apps si hace falta para evitar errores -600
        if !isAppRunning(bundleID: "com.spotify.client") {
            activateApp(bundleID: "com.spotify.client", completion: nil)
        }
        if !isAppRunning(bundleID: "com.google.Chrome") {
            activateApp(bundleID: "com.google.Chrome", completion: nil)
        }

        // Damos un pequeño tiempo y luego pedimos algo "inofensivo" a cada app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Spotify: leer estado (dispara el prompt)
            self.runAppleScript(#"tell application "Spotify" to player state"#)

            // Finder: consultar nombre de la ventana frontal
            self.runAppleScript(#"tell application "Finder" to get name of front window"#)

            // Chrome: consultar título de la ventana frontal
            self.runAppleScript(#"tell application "Google Chrome" to get title of front window"#)

            // Agrega aquí otras apps si querés forzar el prompt (VS Code/Notion no exponen AppleScript útil).
        }
    }

    // MARK: - Utilidades
    private func playPauseSpotifyWithRetry() {
        func tryPlay(_ remaining: Int) {
            if isAppRunning(bundleID: "com.spotify.client") {
                runAppleScript(#"tell application "Spotify" to playpause"#)
            } else if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tryPlay(remaining - 1) }
            } else {
                print("Spotify no inició a tiempo; omitido play/pause.")
            }
        }
        if !isAppRunning(bundleID: "com.spotify.client") {
            activateApp(bundleID: "com.spotify.client", completion: nil)
        }
        tryPlay(10) // 3 s máx
    }

    private func isAppRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    private func sendKey(_ key: Key, flags: CGEventFlags = []) {
        guard let keyCode = keyCodes[key] else { return }
        let src = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private func runAppleScript(_ script: String) {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error { print("AppleScript error:", error) }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// Helpers
enum Key { case t }

private let keyCodes: [Key: CGKeyCode] = [
    .t: CGKeyCode(kVK_ANSI_T)
]

