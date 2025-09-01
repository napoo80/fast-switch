//
//  DasungDDC.swift
//  FastSwitch
//
//  Created by Gaston on 31/08/2025.
//

import Cocoa
import CoreGraphics


enum DitheringMode: Int { case M1 = 1, M2, M3, M4 }
enum RefreshSpeed: Int {
    case fastPP = 1, fastP = 2, fast = 3, blackP = 4, blackPP = 5
}

final class DasungDDC {
    static let shared = DasungDDC()

    /// Índice de display para ddcctl. Con un externo suele ser 1.
    /// Si no aplica, probá 2. También podés exponerlo en Settings.
    var ddcIndex: Int = 1

    @discardableResult
    func setDithering(_ mode: DitheringMode) -> Bool {
        sendVCP(0x07, value: mode.rawValue)
    }

    @discardableResult
    func setRefresh(_ speed: RefreshSpeed) -> Bool {
        sendVCP(0x0C, value: speed.rawValue)
    }

    @discardableResult
    func clearScreen() -> Bool {
        // Comando de “clear” que se ve en implementaciones previas
        sendVCP(0x06, value: 0x03)
    }

    // MARK: - Helpers

    private func sendVCP(_ code: Int, value: Int) -> Bool {
        guard let exe = pathTo("ddcctl") else { return false }
        let args = ["-d", "\(ddcIndex)",
                    "-r", String(format: "0x%02X", code),
                    "-w", "\(value)"]
        return run(exe, args) == 0
    }

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


