import Cocoa
import Foundation
import CoreGraphics



/// Refresher para DASUNG: intenta DDC (m1ddc) → displayplacer → flash negro/blanco.
final class DasungRefresher {

    static let shared = DasungRefresher()

    /// UUIDs conocidos del monitor Dasung en diferentes computadoras
    private let knownDasungUUIDs = [
        "1E6E43E3-2C58-43E0-8813-B7079CD9FEFA", // compu personal
        "E2570BBE-2774-45DC-ACBF-E1BDFB468DD1"  // compu del trabajo
    ]
    
    /// UUID actual detectado del monitor Dasung
    private var _detectedUUID: String?
    
    var dasungDisplayUUID: String {
        if let detected = _detectedUUID {
            return detected
        }
        
        // Buscar cuál de los UUIDs conocidos está conectado
        for uuid in knownDasungUUIDs {
            if NSScreen.screens.contains(where: { $0.displayUUIDString?.caseInsensitiveCompare(uuid) == .orderedSame }) {
                _detectedUUID = uuid
                return uuid
            }
        }
        
        // Fallback al primero si no encuentra ninguno
        return knownDasungUUIDs[0]
    }
    
    var useRotationHop = false


    /// Alias para compatibilidad con código viejo que usa `dasungDisplayID`.
    var dasungDisplayID: String {
        get { dasungDisplayUUID }
        set { _detectedUUID = newValue }
    }

    // ————— API pública —————
    //func refreshPaperlike() {
    //    if refreshViaDDC() { return }
    //    if refreshViaDisplayplacerRotationHop() { return }
    //    refreshViaFlashFallback()
    //}
    
    func refreshPaperlike() {
        if refreshViaDDC() { return }
        // ✅ La rotación solo corre si vos la habilitás explícitamente
        if useRotationHop, refreshViaDisplayplacerRotationHop() { return }
        refreshViaFlashFallback()
    }
    // MARK: A) DDC con m1ddc (opcional)
    private func refreshViaDDC() -> Bool {
        guard let tool = pathTo("m1ddc") else { return false }
        // m1ddc displayuuid:UUID set vcp 0x06 0x03  → “clear screen” en Paperlike
        let status = run(tool, ["displayuuid:\(dasungDisplayUUID)", "set", "vcp", "0x06", "0x03"])
        if status == 0 { print("✅ DASUNG refresh via DDC") }
        return status == 0
    }

    // MARK: B) Hop de rotación con displayplacer (180° → 0°)
    @discardableResult
    private func refreshViaDisplayplacerRotationHop() -> Bool {
        guard let dp = pathTo("displayplacer") else { return false }
        let hop1 = "id:\(dasungDisplayUUID) degree:180"
        let hop2 = "id:\(dasungDisplayUUID) degree:0"
        guard run(dp, [hop1]) == 0 else { return false }
        usleep(120_000) // 120 ms
        let ok = run(dp, [hop2]) == 0
        if ok { print("✅ DASUNG refresh via displayplacer rotation") }
        return ok
    }

    // MARK: C) Fallback: flash negro → blanco sólo en la pantalla DASUNG
    private var flashWindow: NSWindow?

    private func refreshViaFlashFallback() {
        guard let scr = screen(forUUID: dasungDisplayUUID) ?? locateDasungScreen() else {
            print("❌ No encontré la pantalla DASUNG"); return
        }

        let frame = scr.frame
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false, screen: scr)
        // cast explícito para evitar el error de tipos
        w.level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)
        w.isOpaque = true
        w.backgroundColor = .black
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
        self.flashWindow = w

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.flashWindow?.backgroundColor = .white
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self?.flashWindow?.orderOut(nil)
                self?.flashWindow = nil
                print("✅ DASUNG refresh via flash")
            }
        }
    }

    // MARK: Helpers

    private func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { $0.displayUUIDString?.caseInsensitiveCompare(uuid) == .orderedSame }
    }

    /// Fallback por nombre humano.
    private func locateDasungScreen() -> NSScreen? {
        let targets = ["DASUNG", "PAPERLIKE", "PAPERLIKE HD", "PAPERLIKE-HD"]
        return NSScreen.screens.first { s in
            targets.contains { s.localizedName.uppercased().contains($0) }
        }
    }

    private func pathTo(_ name: String) -> String? {
        for base in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let p = base + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Ejecuta un binario y devuelve el status.
    @discardableResult
    private func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus }
        catch { return -1 }
    }

    /// Útil para ver los UUID que macOS detecta.
    func debugDumpDisplays() {
        print("🔍 Buscando monitor Dasung...")
        print("📋 UUIDs conocidos: \(knownDasungUUIDs)")
        print("✅ UUID detectado: \(dasungDisplayUUID)")
        print("")
        for s in NSScreen.screens {
            let isKnown = knownDasungUUIDs.contains { $0.caseInsensitiveCompare(s.displayUUIDString ?? "") == .orderedSame }
            let marker = isKnown ? "🎯" : "🖥️"
            print("\(marker) \(s.localizedName) — uuid: \(s.displayUUIDString ?? "nil") frame: \(s.frame)")
        }
    }
}

