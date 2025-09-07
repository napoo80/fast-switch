//
//  NotificationManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import UserNotifications
import Cocoa
import os.log

// MARK: - NotificationManager Protocol

protocol NotificationManagerDelegate: AnyObject {
    func notificationManager(_ manager: NotificationManager, didReceiveAction actionId: String, with response: UNNotificationResponse)
    func notificationManager(_ manager: NotificationManager, shouldPresentNotification notification: UNNotification) -> UNNotificationPresentationOptions
}

// MARK: - NotificationManager

final class NotificationManager: NSObject {
    
    // MARK: - Singleton
    static let shared = NotificationManager()
    
    // MARK: - Properties
    weak var delegate: NotificationManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "NotificationManager")
    
    // MARK: - Initialization
    private override init() {
        super.init()
        setupNotificationCenter()
    }
    
    // MARK: - Setup
    private func setupNotificationCenter() {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermissions()
    }
    
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                self.logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            } else {
                self.logger.info("Notification permissions granted: \(granted)")
            }
        }
    }
    
    // MARK: - Notification Scheduling
    func scheduleNotification(
        title: String,
        body: String,
        identifier: String,
        sound: String? = nil,
        actions: [UNNotificationAction] = [],
        delay: TimeInterval = 0,
        completion: ((Error?) -> Void)? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .active
        
        // Set sound
        if let soundName = sound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }
        
        // Add category with actions if provided
        if !actions.isEmpty {
            let categoryId = "\(identifier)_category"
            let category = UNNotificationCategory(
                identifier: categoryId,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
            UNUserNotificationCenter.current().setNotificationCategories([category])
            content.categoryIdentifier = categoryId
        }
        
        // Create trigger
        let trigger = delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        
        // Create request
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to schedule notification \(identifier): \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully scheduled notification: \(identifier)")
            }
            completion?(error)
        }
    }
    
    // MARK: - Break Notifications
    func scheduleBreakNotification(
        type: WellnessNotificationType,
        delay: TimeInterval,
        completion: ((Error?) -> Void)? = nil
    ) {
        let actions = [
            UNNotificationAction(
                identifier: "DISMISS_ACTION",
                title: "✅ Tomé el descanso",
                options: []
            ),
            UNNotificationAction(
                identifier: "SNOOZE_ACTION", 
                title: "⏰ Recordar en 5 min",
                options: []
            )
        ]
        
        scheduleNotification(
            title: "\(type.icon) Momento de Descanso",
            body: getWellnessMessage(for: type),
            identifier: "break-\(UUID().uuidString)",
            sound: type.soundName,
            actions: actions,
            delay: delay,
            completion: completion
        )
    }
    
    // MARK: - Deep Focus Notifications
    func scheduleDeepFocusNotification(
        message: String,
        identifier: String,
        delay: TimeInterval,
        completion: ((Error?) -> Void)? = nil
    ) {
        let actions = [
            UNNotificationAction(
                identifier: "CONTINUE_FOCUS_ACTION",
                title: "🧘 Continuar Deep Focus",
                options: []
            ),
            UNNotificationAction(
                identifier: "EXIT_FOCUS_ACTION",
                title: "🚪 Salir del modo",
                options: []
            )
        ]
        
        scheduleNotification(
            title: "🧘 Deep Focus",
            body: message,
            identifier: identifier,
            sound: "Crystal.aiff",
            actions: actions,
            delay: delay,
            completion: completion
        )
    }
    
    // MARK: - Wellness Notifications
    func scheduleWellnessNotification(
        type: WellnessNotificationType,
        customMessage: String? = nil,
        delay: TimeInterval = 0,
        completion: ((Error?) -> Void)? = nil
    ) {
        let message = customMessage ?? getWellnessMessage(for: type)
        
        scheduleNotification(
            title: "\(type.icon) Recordatorio de Bienestar",
            body: message,
            identifier: "wellness-\(type)-\(UUID().uuidString)",
            sound: type.soundName,
            delay: delay,
            completion: completion
        )
    }
    
    // MARK: - Export/Success Notifications
    func scheduleSuccessNotification(
        title: String,
        message: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        scheduleNotification(
            title: title,
            body: message,
            identifier: "success-\(Int(Date().timeIntervalSince1970))",
            sound: "Glass.aiff",
            completion: completion
        )
    }
    
    func scheduleErrorNotification(
        title: String,
        message: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        scheduleNotification(
            title: title,
            body: message,
            identifier: "error-\(Int(Date().timeIntervalSince1970))",
            sound: "Basso.aiff",
            completion: completion
        )
    }
    
    // MARK: - Notification Management
    func removeNotification(withIdentifier identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        logger.info("Removed notification: \(identifier)")
    }
    
    func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        logger.info("Removed all notifications")
    }
    
    // MARK: - Helper Methods
    private func getWellnessMessage(for type: WellnessNotificationType) -> String {
        switch type {
        case .eyeBreak:
            return "Mirá algo a más de 6 metros por 20 segundos. Tus ojos te lo agradecerán."
        case .posturalBreak:
            return "Parate, estirate y movete un poco. Tu espalda necesita un respiro."
        case .hydration:
            return "Momento de hidratarse. Un vaso de agua fresca te hará sentir mejor."
        case .mate:
            return "¿Qué tal un mate? Es hora de la pausa perfecta."
        case .exercise:
            return "Hora de mover el cuerpo. Aunque sea una caminata corta ayuda mucho."
        case .deepBreath:
            return "Respirá profundo 3 veces. Inhalá, retené, exhalá lentamente."
        case .workBreak:
            return "Descanso general. Desconectate un momento y volvé con energía renovada."
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Ask delegate for presentation options, default to showing everything
        let options = delegate?.notificationManager(self, shouldPresentNotification: notification) 
                     ?? [.banner, .sound, .badge]
        completionHandler(options)
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logger.info("Received notification action: \(response.actionIdentifier)")
        
        // Forward to delegate
        delegate?.notificationManager(self, didReceiveAction: response.actionIdentifier, with: response)
        
        completionHandler()
    }
}