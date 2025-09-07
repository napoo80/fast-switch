//
//  MenuBarManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Cocoa
import os.log

private let DISABLE_WALLPAPER = true

// MARK: - Menu Tags

private enum MenuTag {
    static let sessionItem = 100
    static let callToggle = 101  
    static let deepFocus = 102
    static let mateStatus = 103
    
    // Configuration submenu tags
    static let configTesting = 200
    static let config45Min = 201
    static let config60Min = 202
    static let config90Min = 203
    static let configDisable = 204
    
    // Wallpaper tags
    static let wallpaperToggle = 300
    static let wallpaperNow = 301
    static let wallpaper15Min = 302
    static let wallpaper30Min = 303
    static let wallpaper60Min = 304
    static let wallpaperRoot = 305
}

// MARK: - MenuBarManager Protocol

protocol MenuBarManagerDelegate: AnyObject {
    // Menu actions
    func menuBarManager(_ manager: MenuBarManager, requestAutomationPermissions: Void)
    func menuBarManager(_ manager: MenuBarManager, toggleCallStatus: Void)
    func menuBarManager(_ manager: MenuBarManager, toggleDeepFocus: Void)
    func menuBarManager(_ manager: MenuBarManager, resetSession: Void)
    func menuBarManager(_ manager: MenuBarManager, showDashboard: Void)
    func menuBarManager(_ manager: MenuBarManager, showWeeklyReport: Void)
    func menuBarManager(_ manager: MenuBarManager, showYearlyReport: Void)
    func menuBarManager(_ manager: MenuBarManager, exportData: Void)
    func menuBarManager(_ manager: MenuBarManager, showMateProgress: Void)
    func menuBarManager(_ manager: MenuBarManager, setNotificationMode mode: NotificationMode)
    func menuBarManager(_ manager: MenuBarManager, openNotificationPrefs: Void)
    func menuBarManager(_ manager: MenuBarManager, quitApp: Void)
    
    // Wallpaper actions
    func menuBarManager(_ manager: MenuBarManager, toggleWallpaperPhrases: Void)
    func menuBarManager(_ manager: MenuBarManager, changeWallpaperNow: Void)
    func menuBarManager(_ manager: MenuBarManager, setWallpaperInterval minutes: Int)
}

enum NotificationMode {
    case testing
    case interval45
    case interval60
    case interval90
    case disabled
}

// MARK: - Localized Strings

private struct Strings {
    // Main menu items
    static let requestPermissions = "Solicitar permisos…"
    static let sessionTime = "Sesión: 0m"
    static let markAsCall = "🔘 Marcar como llamada"
    static let deepFocusOff = "🧘 Deep Focus: OFF"
    static let resetSession = "🔄 Reiniciar sesión"
    static let reports = "📊 Reportes"
    static let mateStatus = "🧉 Plan de Mate: Cargando..."
    static let configuration = "⚙️ Configuración"
    static let quit = "Salir"
    
    // Reports submenu
    static let showDashboard = "📊 Ver Dashboard Diario"
    static let weeklyReport = "📈 Reporte Semanal"
    static let yearlyReport = "📅 Reporte Anual"
    static let exportData = "💾 Exportar Datos"
    
    // Configuration submenu
    static let testingMode = "🔔 Testing: 1-5-10min"
    static let reminders45min = "🔔 Recordatorios cada 45m"
    static let reminders60min = "🔔 Recordatorios cada 60m" 
    static let reminders90min = "🔔 Recordatorios cada 90m"
    static let disableReminders = "🔕 Desactivar recordatorios"
    static let notificationSettings = "⚙️ Ajustes de Notificaciones…"
    
    // Wallpaper submenu
    static let wallpaperPhrases = "🖼️ Wallpaper de frases"
    static let wallpaperOff = "OFF"
    static let wallpaperChangeNow = "Cambiar ahora"
    static let wallpaperInterval15 = "Intervalo 15m"
    static let wallpaperInterval30 = "Intervalo 30m"
    static let wallpaperInterval60 = "Intervalo 60m"
    
    // Dynamic status updates
    static let inCall = "📞 En llamada:"
    static let sessionLabel = "⏰ Sesión:"
    static let deepFocusOn = "🧘 Deep Focus: ON"
    static let matePhaseStatus = "🧉 Fase %d: %d/%d termos %@"
}

// MARK: - MenuBarManager

final class MenuBarManager: NSObject {
    
    // MARK: - Singleton
    static let shared = MenuBarManager()
    
    // MARK: - Properties
    weak var delegate: MenuBarManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "MenuBarManager")
    
    private var statusItem: NSStatusItem!
    private var wallpaperEnabled = false
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        logger.info("📋 MenuBarManager initialized")
    }
    
    // MARK: - Public API
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "F→"
        
        let menu = buildMainMenu()
        statusItem.menu = menu
        
        logger.info("📋 Menu created with \(menu.items.count) items")
    }
    
    func updateTitle(_ title: String) {
        DispatchQueue.main.async {
            self.statusItem.button?.title = title
        }
    }
    
    func updateSessionTime(duration: TimeInterval, isInCall: Bool = false) {
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu,
                  let sessionItem = menu.item(withTag: MenuTag.sessionItem) else { return }
            
            let hours = Int(duration) / 3600
            let minutes = Int(duration) % 3600 / 60
            let timeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            
            let statusText = isInCall ? "\(Strings.inCall) \(timeString)" : "\(Strings.sessionLabel) \(timeString)"
            sessionItem.title = statusText
        }
    }
    
    func updateDeepFocusStatus(_ isEnabled: Bool) {
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu,
                  let focusItem = menu.item(withTag: MenuTag.deepFocus) else { return }
            
            focusItem.title = isEnabled ? Strings.deepFocusOn : Strings.deepFocusOff
        }
    }
    
    func updateCallStatus(_ isInCall: Bool) {
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu,
                  let callItem = menu.item(withTag: MenuTag.callToggle) else { return }
            
            callItem.title = isInCall ? "📞 En llamada activa" : Strings.markAsCall
        }
    }
    
    func updateMateStatus(phase: Int, current: Int, target: Int) {
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu,
                  let mateItem = menu.item(withTag: MenuTag.mateStatus) else { return }
            
            let status = current >= target ? "✅" : "🔄"
            mateItem.title = String(format: Strings.matePhaseStatus, phase, current, target, status)
        }
    }
    
    func updateConfigurationMenu(mode: NotificationMode) {
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu else { return }
            
            // Find the configuration submenu
            var configSubmenu: NSMenu?
            for item in menu.items {
                if item.title == Strings.configuration, let submenu = item.submenu {
                    configSubmenu = submenu
                    break
                }
            }
            
            guard let configMenu = configSubmenu else { return }
            
            // Reset all states
            let configTags = [MenuTag.configTesting, MenuTag.config45Min, MenuTag.config60Min, 
                             MenuTag.config90Min, MenuTag.configDisable]
            
            for tag in configTags {
                configMenu.item(withTag: tag)?.state = .off
            }
            
            // Set current mode state
            let activeTag: Int = {
                switch mode {
                case .testing: return MenuTag.configTesting
                case .interval45: return MenuTag.config45Min
                case .interval60: return MenuTag.config60Min
                case .interval90: return MenuTag.config90Min
                case .disabled: return MenuTag.configDisable
                }
            }()
            
            configMenu.item(withTag: activeTag)?.state = .on
        }
    }
    
    func updateWallpaperMenu(isEnabled: Bool, intervalMinutes: Int) {
        wallpaperEnabled = isEnabled
        
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu,
                  let wallpaperRoot = menu.items.first(where: { $0.submenu?.item(withTag: MenuTag.wallpaperToggle) != nil })?.submenu else { return }
            
            // Update toggle state
            if let toggle = wallpaperRoot.item(withTag: MenuTag.wallpaperToggle) {
                toggle.title = isEnabled ? "ON (\(intervalMinutes)m)" : Strings.wallpaperOff
            }
            
            // Update interval selection
            let intervalTags = [(MenuTag.wallpaper15Min, 15), (MenuTag.wallpaper30Min, 30), (MenuTag.wallpaper60Min, 60)]
            for (tag, minutes) in intervalTags {
                wallpaperRoot.item(withTag: tag)?.state = (intervalMinutes == minutes) ? .on : .off
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func buildMainMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Permissions request
        menu.addItem(NSMenuItem(title: Strings.requestPermissions, 
                               action: #selector(requestPermissions), 
                               keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Usage tracking items
        let sessionItem = NSMenuItem(title: Strings.sessionTime, action: nil, keyEquivalent: "")
        sessionItem.tag = MenuTag.sessionItem
        menu.addItem(sessionItem)
        
        let callToggleItem = NSMenuItem(title: Strings.markAsCall, 
                                      action: #selector(toggleCall), 
                                      keyEquivalent: "")
        callToggleItem.tag = MenuTag.callToggle
        menu.addItem(callToggleItem)
        
        let deepFocusItem = NSMenuItem(title: Strings.deepFocusOff, 
                                     action: #selector(toggleFocus), 
                                     keyEquivalent: "")
        deepFocusItem.tag = MenuTag.deepFocus
        menu.addItem(deepFocusItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: Strings.resetSession, 
                               action: #selector(resetSessionAction), 
                               keyEquivalent: ""))
        
        // Reports submenu
        menu.addItem(buildReportsSubmenu())
        
        // Mate status
        let mateStatusItem = NSMenuItem(title: Strings.mateStatus, 
                                      action: #selector(showMateAction), 
                                      keyEquivalent: "")
        mateStatusItem.tag = MenuTag.mateStatus
        menu.addItem(mateStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Wallpaper menu (conditional)
        if !DISABLE_WALLPAPER {
            menu.addItem(buildWallpaperSubmenu())
        }
        
        // Configuration submenu
        menu.addItem(buildConfigurationSubmenu())
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: Strings.quit, 
                               action: #selector(quitAction), 
                               keyEquivalent: "q"))
        
        return menu
    }
    
    private func buildReportsSubmenu() -> NSMenuItem {
        let reportsMenu = NSMenu()
        let reportsItem = NSMenuItem(title: Strings.reports, action: nil, keyEquivalent: "")
        reportsItem.submenu = reportsMenu
        
        reportsMenu.addItem(NSMenuItem(title: Strings.showDashboard, 
                                      action: #selector(showDashboardAction), 
                                      keyEquivalent: ""))
        reportsMenu.addItem(NSMenuItem(title: Strings.weeklyReport, 
                                      action: #selector(showWeeklyAction), 
                                      keyEquivalent: ""))
        reportsMenu.addItem(NSMenuItem(title: Strings.yearlyReport, 
                                      action: #selector(showYearlyAction), 
                                      keyEquivalent: ""))
        reportsMenu.addItem(NSMenuItem.separator())
        reportsMenu.addItem(NSMenuItem(title: Strings.exportData, 
                                      action: #selector(exportDataAction), 
                                      keyEquivalent: ""))
        
        return reportsItem
    }
    
    private func buildConfigurationSubmenu() -> NSMenuItem {
        let configMenu = NSMenu()
        let configItem = NSMenuItem(title: Strings.configuration, action: nil, keyEquivalent: "")
        configItem.submenu = configMenu
        
        let testingItem = NSMenuItem(title: Strings.testingMode, 
                                   action: #selector(setTestingMode), 
                                   keyEquivalent: "")
        testingItem.tag = MenuTag.configTesting
        configMenu.addItem(testingItem)
        
        let interval45Item = NSMenuItem(title: Strings.reminders45min, 
                                      action: #selector(set45MinMode), 
                                      keyEquivalent: "")
        interval45Item.tag = MenuTag.config45Min
        configMenu.addItem(interval45Item)
        
        let interval60Item = NSMenuItem(title: Strings.reminders60min, 
                                      action: #selector(set60MinMode), 
                                      keyEquivalent: "")
        interval60Item.tag = MenuTag.config60Min
        configMenu.addItem(interval60Item)
        
        let interval90Item = NSMenuItem(title: Strings.reminders90min, 
                                      action: #selector(set90MinMode), 
                                      keyEquivalent: "")
        interval90Item.tag = MenuTag.config90Min
        configMenu.addItem(interval90Item)
        
        configMenu.addItem(NSMenuItem.separator())
        
        let disableItem = NSMenuItem(title: Strings.disableReminders, 
                                   action: #selector(setDisabledMode), 
                                   keyEquivalent: "")
        disableItem.tag = MenuTag.configDisable
        configMenu.addItem(disableItem)
        
        configMenu.addItem(NSMenuItem.separator())
        configMenu.addItem(NSMenuItem(title: Strings.notificationSettings, 
                                     action: #selector(openNotificationAction), 
                                     keyEquivalent: ""))
        
        return configItem
    }
    
    private func buildWallpaperSubmenu() -> NSMenuItem {
        let wallpaperMenu = NSMenu()
        let wallpaperItem = NSMenuItem(title: Strings.wallpaperPhrases, action: nil, keyEquivalent: "")
        wallpaperItem.submenu = wallpaperMenu
        wallpaperItem.tag = MenuTag.wallpaperRoot
        
        let toggleItem = NSMenuItem(title: Strings.wallpaperOff, 
                                  action: #selector(toggleWallpaperAction), 
                                  keyEquivalent: "")
        toggleItem.tag = MenuTag.wallpaperToggle
        wallpaperMenu.addItem(toggleItem)
        
        let nowItem = NSMenuItem(title: Strings.wallpaperChangeNow, 
                               action: #selector(changeWallpaperAction), 
                               keyEquivalent: "")
        nowItem.tag = MenuTag.wallpaperNow
        wallpaperMenu.addItem(nowItem)
        
        wallpaperMenu.addItem(NSMenuItem.separator())
        
        let intervals = [(Strings.wallpaperInterval15, #selector(setWallpaper15), MenuTag.wallpaper15Min, 15),
                        (Strings.wallpaperInterval30, #selector(setWallpaper30), MenuTag.wallpaper30Min, 30),
                        (Strings.wallpaperInterval60, #selector(setWallpaper60), MenuTag.wallpaper60Min, 60)]
        
        for (title, action, tag, _) in intervals {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.tag = tag
            wallpaperMenu.addItem(item)
        }
        
        wallpaperMenu.addItem(NSMenuItem.separator())
        return wallpaperItem
    }
    
    // MARK: - Menu Actions
    
    @objc private func requestPermissions() {
        delegate?.menuBarManager(self, requestAutomationPermissions: ())
    }
    
    @objc private func toggleCall() {
        delegate?.menuBarManager(self, toggleCallStatus: ())
    }
    
    @objc private func toggleFocus() {
        delegate?.menuBarManager(self, toggleDeepFocus: ())
    }
    
    @objc private func resetSessionAction() {
        delegate?.menuBarManager(self, resetSession: ())
    }
    
    @objc private func showDashboardAction() {
        delegate?.menuBarManager(self, showDashboard: ())
    }
    
    @objc private func showWeeklyAction() {
        delegate?.menuBarManager(self, showWeeklyReport: ())
    }
    
    @objc private func showYearlyAction() {
        delegate?.menuBarManager(self, showYearlyReport: ())
    }
    
    @objc private func exportDataAction() {
        delegate?.menuBarManager(self, exportData: ())
    }
    
    @objc private func showMateAction() {
        delegate?.menuBarManager(self, showMateProgress: ())
    }
    
    @objc private func setTestingMode() {
        delegate?.menuBarManager(self, setNotificationMode: .testing)
    }
    
    @objc private func set45MinMode() {
        delegate?.menuBarManager(self, setNotificationMode: .interval45)
    }
    
    @objc private func set60MinMode() {
        delegate?.menuBarManager(self, setNotificationMode: .interval60)
    }
    
    @objc private func set90MinMode() {
        delegate?.menuBarManager(self, setNotificationMode: .interval90)
    }
    
    @objc private func setDisabledMode() {
        delegate?.menuBarManager(self, setNotificationMode: .disabled)
    }
    
    @objc private func openNotificationAction() {
        delegate?.menuBarManager(self, openNotificationPrefs: ())
    }
    
    @objc private func quitAction() {
        delegate?.menuBarManager(self, quitApp: ())
    }
    
    // MARK: - Wallpaper Actions
    
    @objc private func toggleWallpaperAction() {
        delegate?.menuBarManager(self, toggleWallpaperPhrases: ())
    }
    
    @objc private func changeWallpaperAction() {
        delegate?.menuBarManager(self, changeWallpaperNow: ())
    }
    
    @objc private func setWallpaper15() {
        delegate?.menuBarManager(self, setWallpaperInterval: 15)
    }
    
    @objc private func setWallpaper30() {
        delegate?.menuBarManager(self, setWallpaperInterval: 30)
    }
    
    @objc private func setWallpaper60() {
        delegate?.menuBarManager(self, setWallpaperInterval: 60)
    }
}