//
//  WallpaperPhraseManager.swift
//  FastSwitch
//
//  Created by Gaston on 30/08/2025.
//
//  Requiere: import AppKit, Foundation

import AppKit
import Foundation
import CoreGraphics // arriba si no está

// Feature flag handled via AppConfig

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
        guard AppConfig.wallpaperEnabled else { return }

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

    func updateNow() {
        guard AppConfig.wallpaperEnabled else { return }

        applyPhraseWallpaper()
    }

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
            if isEInk(screen) { continue }
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

        // Fondo
        if let currentURL = NSWorkspace.shared.desktopImageURL(for: screen),
           let bg = NSImage(contentsOf: currentURL) {
            bg.draw(in: CGRect(origin: .zero, size: sizePx), from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            let ctx = NSGraphicsContext.current!.cgContext
            let colors = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0,1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: sizePx.width, y: sizePx.height), options: [])
        }

        // Caja semitransparente
        let margin: CGFloat = 120 * scale
        let rect = CGRect(x: margin, y: margin, width: sizePx.width - 2*margin, height: sizePx.height - 2*margin)
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 24*scale, yRadius: 24*scale)
        NSColor(calibratedWhite: 0.0, alpha: 0.36).setFill()
        bgPath.fill()

        // Texto
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let baseFont = NSFont.systemFont(ofSize: max(28, min(64, sizePts.width/22)), weight: .semibold)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 8; shadow.shadowOffset = .zero

        let attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]

        let str = NSAttributedString(string: "\u{201C}\(phrase)\u{201D}", attributes: attrs)
        let textRect = str.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
        let drawOrigin = CGPoint(x: rect.midX - textRect.width/2, y: rect.midY - textRect.height/2)
        str.draw(with: CGRect(origin: drawOrigin, size: textRect.size))

        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: sizePts)
        img.addRepresentation(rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "wallpaper", code: 2, userInfo: [NSLocalizedDescriptionKey:"PNG fail"]) }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = tmpDir.appendingPathComponent("FastSwitch-Wallpaper-\(screen.displayID).png")
        try data.write(to: out, options: .atomic)
        return out
    }
    
    private func isEInk(_ screen: NSScreen) -> Bool {
        let name = screen.localizedName.lowercased()
        if name.contains("dasung") || name.contains("paperlike") { return true }
        if let unmanaged = CGDisplayCreateUUIDFromDisplayID(screen.displayID) {
            let uuid = unmanaged.takeRetainedValue()
            let str = CFUUIDCreateString(nil, uuid) as String
            if str.caseInsensitiveCompare(DasungRefresher.shared.dasungDisplayID) == .orderedSame {
                return true
            }
        }
        let sz = screen.frame.size
        if sz.width <= 2200 && sz.height <= 1650 && screen.backingScaleFactor == 1.0 { return true }
        return false
    }
}

