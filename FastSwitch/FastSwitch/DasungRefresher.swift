//
//  DasungRefresher.swift
//  FastSwitch
//
//  Created by Gaston on 31/08/2025.
//

import Cocoa
import Foundation

/// Lightweight, zero-dependency DASUNG refresher
/// Strategy A: rotate 180° and back via `displayplacer` (forces full e-ink repaint)
/// Strategy B: quick black→white flash fullscreen on the Paperlike screen
final class DasungRefresher {

    static let shared = DasungRefresher()

    /// Set this once if you know the Paperlike display UUID (from `displayplacer list`)
    /// You already used this id in your presets:
    ///   id:1E6E43E3-2C58-43E0-8813-B7079CD9FEFA
    /// If yours differs, change the value below.
    var dasungDisplayID = "1E6E43E3-2C58-43E0-8813-B7079CD9FEFA"

    /// Top-level “refresh” you’ll call from F5
    func refreshPaperlike() {
        if refreshViaDisplayplacerRotationHop() == false {
            // If displayplacer isn’t present or the id didn’t match, do a visual flash fallback.
            refreshViaFlashFallback()
        }
    }

    // MARK: - Strategy A: rotation hop with displayplacer

    @discardableResult
    private func refreshViaDisplayplacerRotationHop() -> Bool {
        guard let dp = pathTo("displayplacer") else { return false }

        // Two very fast calls: rotate 180°, then back to 0°.
        // Only targets the DASUNG by id; it won’t disturb other displays.
        let hop1 = #"id:\#(dasungDisplayID) degree:180"#
        let hop2 = #"id:\#(dasungDisplayID) degree:0"#

        let ok1 = run(dp, [hop1]) == 0
        if !ok1 { return false }

        // tiny delay to let the compositor flip frames (kept super short)
        usleep(120_000) // 120 ms

        let ok2 = run(dp, [hop2]) == 0
        return ok2
    }

    // MARK: - Strategy B: fullscreen black→white flash (no external tools)

    private var flashWindow: NSWindow?

    private func refreshViaFlashFallback() {
        guard let screen = locateDasungScreen() ?? NSScreen.screens.last else { return }

        // Build a borderless, always-on-top window on the Paperlike screen
        let w = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        w.level = .screenSaver
        w.isOpaque = true
        w.backgroundColor = .black
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        w.makeKeyAndOrderFront(nil)
        self.flashWindow = w

        // Black → White → remove (fast). This hard-refreshes the e-ink panel visually.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.flashWindow?.backgroundColor = .white
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self?.flashWindow?.orderOut(nil)
                self?.flashWindow = nil
            }
        }
    }

    // MARK: - Helpers

    /// Try to find the DASUNG screen by its human name first, else nil.
    private func locateDasungScreen() -> NSScreen? {
        let targets = ["DASUNG", "Paperlike", "Paperlike HD", "Paperlike-HD"]
        if let named = NSScreen.screens.first(where: { s in
            let name = s.localizedName.uppercased()
            return targets.contains(where: { name.contains($0.uppercased()) })
        }) { return named }
        return nil
    }

    /// Resolve an executable in common Homebrew/System paths.
    private func pathTo(_ name: String) -> String? {
        for base in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let p = base + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    @discardableResult
    private func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }
}
