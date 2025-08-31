//
//  WallpaperPhraseManager.swift
//  FastSwitch
//
//  Created by Gaston on 30/08/2025.
//
//  Requiere: import AppKit, Foundation

import AppKit
import Foundation

// MARK: - NSScreen helper
private extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

// MARK: - Manager
final class WallpaperPhraseManager {
    static let shared = WallpaperPhraseManager()
    private init() {}

    // Public API
    var isEnabled: Bool { timer != nil }
    var interval: TimeInterval = 30 * 60 // 30m por defecto

    /// Si lo dejás vacío, intenta usar las frases de tu app (ver integración abajo)
    var phrases: [String] = []

    func start(phrases: [String]? = nil, interval: TimeInterval? = nil) {
        if let phrases { self.phrases = phrases }
        if let interval { self.interval = interval }
        captureOriginalWallpapersIfNeeded()
        scheduleTimer()
        updateNow()
    }

    func stop(restoringOriginal: Bool = true) {
        timer?.invalidate(); timer = nil
        if restoringOriginal { restoreOriginalWallpapers() }
    }

    func updateNow() { applyPhraseWallpaper() }

    // MARK: - Internals
    private var timer: Timer?
    private var lastIndex: Int?
    private var originalByDisplayID: [CGDirectDisplayID: URL] = [:]

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.applyPhraseWallpaper()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func captureOriginalWallpapersIfNeeded() {
        for screen in NSScreen.screens {
            let id = screen.displayID
            if originalByDisplayID[id] == nil,
               let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                originalByDisplayID[id] = url
            }
        }
    }

    private func restoreOriginalWallpapers() {
        for screen in NSScreen.screens {
            let id = screen.displayID
            if let url = originalByDisplayID[id] {
                setWallpaper(url: url, on: screen)
            }
        }
    }

    private func applyPhraseWallpaper() {
        let phrase = nextPhrase()
        for screen in NSScreen.screens {
            do {
                let url = try renderPhrase(phrase, for: screen)
                setWallpaper(url: url, on: screen)
            } catch {
                NSLog("[Wallpaper] render error: \(error)")
            }
        }
    }

    private func nextPhrase() -> String {
        guard !phrases.isEmpty else { return "Pequeños pasos, grandes logros" }
        var idx: Int
        repeat { idx = Int.random(in: 0..<phrases.count) } while phrases.count > 1 && idx == lastIndex
        lastIndex = idx
        return phrases[idx]
    }

    private func setWallpaper(url: URL, on screen: NSScreen) {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        options[.allowClipping] = true
        do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options) }
        catch { NSLog("[Wallpaper] set error: \(error)") }
    }

    // MARK: - Render
    private func renderPhrase(_ phrase: String, for screen: NSScreen) throws -> URL {
        let scale = screen.backingScaleFactor
        let sizePts = screen.frame.size
        let sizePx = CGSize(width: sizePts.width * scale, height: sizePts.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(sizePx.width),
            pixelsHigh: Int(sizePx.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw NSError(domain: "wallpaper", code: 1, userInfo: [NSLocalizedDescriptionKey:"No bitmap rep"]) }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        // Fondo: usa el wallpaper actual si existe, sino un degradé
        if let currentURL = NSWorkspace.shared.desktopImageURL(for: screen),
           let bg = NSImage(contentsOf: currentURL) {
            bg.draw(in: CGRect(origin: .zero, size: sizePx), from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            let ctx = NSGraphicsContext.current!.cgContext
            let colors = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0,1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: sizePx.width, y: sizePx.height), options: [])
        }

        // Caja semitransparente para legibilidad
        let margin: CGFloat = 120 * scale
        let rect = CGRect(x: margin, y: margin, width: sizePx.width - 2*margin, height: sizePx.height - 2*margin)
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 24*scale, yRadius: 24*scale)
        NSColor(calibratedWhite: 0.0, alpha: 0.36).setFill()
        bgPath.fill()

        // Atributos de texto
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        // Tamaño de fuente en función del ancho
        let baseFont = NSFont.systemFont(ofSize: max(28, min(64, sizePts.width/22)), weight: .semibold)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 8; shadow.shadowOffset = .zero

        let attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]

        // Dibujar frase centrada en la caja
        let str = NSAttributedString(string: "\u{201C}\(phrase)\u{201D}", attributes: attrs)
        let textRect = str.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
        let drawOrigin = CGPoint(x: rect.midX - textRect.width/2, y: rect.midY - textRect.height/2)
        str.draw(with: CGRect(origin: drawOrigin, size: textRect.size))

        NSGraphicsContext.restoreGraphicsState()

        // Armar NSImage y exportar a PNG temporal
        let img = NSImage(size: sizePts)
        img.addRepresentation(rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "wallpaper", code: 2, userInfo: [NSLocalizedDescriptionKey:"PNG fail"]) }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = tmpDir.appendingPathComponent("FastSwitch-Wallpaper-\(screen.displayID).png")
        try data.write(to: out, options: .atomic)
        return out
    }
}

// ==============================================================
// INTEGRACIÓN con tu AppDelegate existente
// --------------------------------------------------------------
// 1) Conservá tus structs/phrase system. Este manager puede reutilizar
//    `motivationalPhrases.map { $0.text }` de tu app.
// 2) Agregá estas propiedades y acciones al AppDelegate.

extension AppDelegate {
    // Item tags para actualizar estado desde el menú
    private enum WPTag { static let toggle = 300; static let now = 301; static let i15 = 302; static let i30 = 303; static let i60 = 304 }

    @objc func togglePhraseWallpaper() {
        if WallpaperPhraseManager.shared.isEnabled {
            WallpaperPhraseManager.shared.stop()
        } else {
            // Reutiliza tus frases si las tenés cargadas
            let fallback = ["Concéntrate en el proceso, no en el resultado", "La consistencia vence al talento", "Pequeños pasos, grandes logros", "Cada día es una nueva oportunidad", "El descanso es parte del trabajo"]
            let list = motivationalPhrases.isEmpty ? fallback : motivationalPhrases.map { $0.text }
            WallpaperPhraseManager.shared.start(phrases: list, interval: WallpaperPhraseManager.shared.interval)
        }
        updateWallpaperMenuState()
    }

    @objc func changePhraseNow() {
        WallpaperPhraseManager.shared.updateNow()
    }

    @objc func setWPInterval15() { WallpaperPhraseManager.shared.interval = 15*60; WallpaperPhraseManager.shared.updateNow(); updateWallpaperMenuState() }
    @objc func setWPInterval30() { WallpaperPhraseManager.shared.interval = 30*60; WallpaperPhraseManager.shared.updateNow(); updateWallpaperMenuState() }
    @objc func setWPInterval60() { WallpaperPhraseManager.shared.interval = 60*60; WallpaperPhraseManager.shared.updateNow(); updateWallpaperMenuState() }

    func injectWallpaperMenu(into menu: NSMenu) {
        let wpMenu = NSMenu()
        let root = NSMenuItem(title: "🖼️ Wallpaper de frases", action: nil, keyEquivalent: "")
        root.submenu = wpMenu

        let toggle = NSMenuItem(title: "OFF", action: #selector(togglePhraseWallpaper), keyEquivalent: "")
        toggle.tag = WPTag.toggle; toggle.target = self
        wpMenu.addItem(toggle)

        let now = NSMenuItem(title: "Cambiar ahora", action: #selector(changePhraseNow), keyEquivalent: "")
        now.tag = WPTag.now; now.target = self
        wpMenu.addItem(now)

        wpMenu.addItem(NSMenuItem.separator())
        let i15 = NSMenuItem(title: "Intervalo 15m", action: #selector(setWPInterval15), keyEquivalent: "")
        i15.tag = WPTag.i15; i15.target = self; wpMenu.addItem(i15)
        let i30 = NSMenuItem(title: "Intervalo 30m", action: #selector(setWPInterval30), keyEquivalent: "")
        i30.tag = WPTag.i30; i30.target = self; wpMenu.addItem(i30)
        let i60 = NSMenuItem(title: "Intervalo 60m", action: #selector(setWPInterval60), keyEquivalent: "")
        i60.tag = WPTag.i60; i60.target = self; wpMenu.addItem(i60)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(root)
        updateWallpaperMenuState()
    }

    
    func updateWallpaperMenuState(_ menu: NSMenu) {
        // Buscamos el submenu que contiene nuestro toggle por tag
        let submenus = menu.items.compactMap { $0.submenu }
        guard let wpRoot = submenus.first(where: { $0.item(withTag: WPTag.toggle) != nil }) else { return }

        // Título del toggle
        if let toggle = wpRoot.item(withTag: WPTag.toggle) {
            let mins = Int(WallpaperPhraseManager.shared.interval / 60)
            toggle.title = WallpaperPhraseManager.shared.isEnabled ? "ON (\(mins)m)" : "OFF"
        }

        // Marcar el intervalo activo (⚠️ tipado explícito para evitar “Cannot infer .on”)
        let current = Int(WallpaperPhraseManager.shared.interval)
        let pairs: [(Int, Int)] = [(WPTag.i15, 900), (WPTag.i30, 1800), (WPTag.i60, 3600)]
        for (tag, secs) in pairs {
            let state: NSControl.StateValue = (current == secs) ? .on : .off
            wpRoot.item(withTag: tag)?.state = state
        }
    }
    
    func updateWallpaperMenuState() {
        guard let menu = statusItem.menu, let wpRoot = menu.items.first(where: { $0.submenu?.items.contains(where: { $0.tag == WPTag.toggle }) == true })?.submenu else { return }
        if let toggle = wpRoot.item(withTag: WPTag.toggle) {
            toggle.title = WallpaperPhraseManager.shared.isEnabled ? "ON (\(Int(WallpaperPhraseManager.shared.interval/60))m)" : "OFF"
        }
        // marquita al intervalo activo
        let current = Int(WallpaperPhraseManager.shared.interval)
        [WPTag.i15: 900, WPTag.i30: 1800, WPTag.i60: 3600].forEach { tag, secs in
            wpRoot.item(withTag: tag)?.state = (current == secs) ? .on : .off
        }
    }
}

/*
USO RÁPIDO
---------
1) Agregá este archivo al proyecto.
2) En tu AppDelegate.applicationDidFinishLaunching(_:) justo después de construir el menú principal, llamá:

    // ... ya creaste `menu` y lo asignaste a statusItem.menu
    injectWallpaperMenu(into: menu)

3) (Opcional) Para arrancar ON desde el inicio:

    let frases = motivationalPhrases.isEmpty ? ["Pequeños pasos, grandes logros"] : motivationalPhrases.map { $0.text }
    WallpaperPhraseManager.shared.start(phrases: frases, interval: 30*60)

Notas
-----
- El manager renderiza un PNG por pantalla, reutilizando el wallpaper actual como fondo + una caja translúcida con la frase.
- Al detener (stop), restaura el wallpaper original.
- Evita repetir la misma frase consecutivamente.
- Podés reemplazar la tipografía/estilo dentro de `renderPhrase(_:for:)`.
*/
