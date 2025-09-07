//
//  WellnessManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import UserNotifications
import os.log

// MARK: - WellnessManager Protocol

protocol WellnessManagerDelegate: AnyObject {
    func wellnessManager(_ manager: WellnessManager, needsNotification request: UNNotificationRequest)
    func wellnessManager(_ manager: WellnessManager, didUpdateMateProgress thermos: Int, target: Int)
    func wellnessManager(_ manager: WellnessManager, didAdvancePhase newPhase: Int)
    func wellnessManager(_ manager: WellnessManager, didSaveDailyReflection reflection: DailyReflection)
}

// MARK: - WellnessManager

final class WellnessManager: NSObject {
    
    // MARK: - Singleton
    static let shared = WellnessManager()
    
    // MARK: - Properties
    weak var delegate: WellnessManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "WellnessManager")
    
    // Wellness feature toggles (opt-in design)
    private var isMateTrackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "WellnessMateTrackingEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "WellnessMateTrackingEnabled") }
    }
    
    private var isExerciseTrackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "WellnessExerciseTrackingEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "WellnessExerciseTrackingEnabled") }
    }
    
    private var isMoodTrackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "WellnessMoodTrackingEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "WellnessMoodTrackingEnabled") }
    }
    
    private var isDailyReflectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "WellnessDailyReflectionEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "WellnessDailyReflectionEnabled") }
    }
    
    // Master wellness toggle
    private var isWellnessEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "WellnessEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "WellnessEnabled") }
    }
    
    // Mate reduction plan
    private var mateReductionPlan = MateReductionPlan()
    private var mateScheduleTimer: Timer?
    private var mateNotificationHistory: [Date] = []
    
    // Wellness question scheduling
    private var wellnessQuestionTimer: Timer?
    private let wellnessQuestionInterval: TimeInterval = 1800 // 30 minutes
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        loadMateReductionPlan()
        logger.info("🌱 WellnessManager initialized")
    }
    
    // MARK: - Public API - Feature Toggles
    
    /// Enable/disable entire wellness system
    func setWellnessEnabled(_ enabled: Bool) {
        isWellnessEnabled = enabled
        
        if enabled {
            startWellnessTracking()
            logger.info("🌱 Wellness tracking enabled")
        } else {
            stopWellnessTracking()
            logger.info("🚫 Wellness tracking disabled")
        }
    }
    
    /// Check if wellness is enabled
    func getWellnessEnabled() -> Bool {
        return isWellnessEnabled
    }
    
    /// Configure individual wellness features
    func setMateTrackingEnabled(_ enabled: Bool) {
        isMateTrackingEnabled = enabled
        if enabled && isWellnessEnabled {
            scheduleMateReminders()
        } else {
            mateScheduleTimer?.invalidate()
        }
        logger.info("🧉 Mate tracking: \(enabled ? "enabled" : "disabled")")
    }
    
    func setExerciseTrackingEnabled(_ enabled: Bool) {
        isExerciseTrackingEnabled = enabled
        logger.info("🏃 Exercise tracking: \(enabled ? "enabled" : "disabled")")
    }
    
    func setMoodTrackingEnabled(_ enabled: Bool) {
        isMoodTrackingEnabled = enabled
        logger.info("😊 Mood tracking: \(enabled ? "enabled" : "disabled")")
    }
    
    func setDailyReflectionEnabled(_ enabled: Bool) {
        isDailyReflectionEnabled = enabled
        logger.info("📝 Daily reflection: \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Wellness Tracking
    
    private func startWellnessTracking() {
        guard isWellnessEnabled else { return }
        
        // Schedule wellness question timer
        wellnessQuestionTimer = Timer.scheduledTimer(withTimeInterval: wellnessQuestionInterval, repeats: true) { [weak self] _ in
            self?.checkForWellnessQuestions()
        }
        
        // Schedule mate reminders if enabled
        if isMateTrackingEnabled {
            scheduleMateReminders()
        }
    }
    
    private func stopWellnessTracking() {
        wellnessQuestionTimer?.invalidate()
        wellnessQuestionTimer = nil
        mateScheduleTimer?.invalidate()
        mateScheduleTimer = nil
    }
    
    private func checkForWellnessQuestions() {
        guard isWellnessEnabled else { return }
        
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // Only ask during work hours (9 AM - 6 PM)
        guard hour >= 9 && hour <= 18 else {
            logger.debug("⏰ Outside work hours, skipping wellness questions")
            return
        }
        
        // Randomly decide which type of question to ask
        let questionTypes = getEnabledQuestionTypes()
        guard !questionTypes.isEmpty else { return }
        
        let randomQuestion = questionTypes.randomElement()!
        
        switch randomQuestion {
        case "mate" where isMateTrackingEnabled:
            askMateQuestion()
        case "exercise" where isExerciseTrackingEnabled:
            askExerciseQuestion()
        case "mood" where isMoodTrackingEnabled:
            askMoodQuestion()
        default:
            break
        }
    }
    
    private func getEnabledQuestionTypes() -> [String] {
        var types: [String] = []
        if isMateTrackingEnabled { types.append("mate") }
        if isExerciseTrackingEnabled { types.append("exercise") }
        if isMoodTrackingEnabled { types.append("mood") }
        return types
    }
    
    // MARK: - Mate Tracking
    
    func getMateReductionPlan() -> MateReductionPlan {
        return mateReductionPlan
    }
    
    func recordMate(thermosCount: Int) {
        guard isMateTrackingEnabled && isWellnessEnabled else { return }
        
        logger.info("🧉 Recording mate: \(thermosCount) thermos")
        
        // Update mate reduction progress
        updateMateReductionProgress()
        
        let target = mateReductionPlan.getCurrentTargetThermos()
        delegate?.wellnessManager(self, didUpdateMateProgress: thermosCount, target: target)
    }
    
    private func updateMateReductionProgress() {
        // Reset daily count at midnight
        let calendar = Calendar.current
        if !calendar.isDate(Date(), equalTo: mateReductionPlan.startDate, toGranularity: .day) {
            // New day - reset if needed
        }
        
        // Check if we should advance phase
        if mateReductionPlan.shouldAdvancePhase() {
            advanceMateReductionPhase()
        }
    }
    
    private func advanceMateReductionPhase() {
        let newPhase = min(mateReductionPlan.currentPhase + 1, 3)
        mateReductionPlan.currentPhase = newPhase
        
        saveMateReductionPlan()
        
        logger.info("📈 Mate reduction advanced to phase \(newPhase)")
        
        // Schedule new reminders for new phase
        scheduleMateReminders()
        
        let target = mateReductionPlan.getCurrentTargetThermos()
        
        // Send congratulations notification
        sendMatePhaseAdvanceNotification(newPhase: newPhase, newTarget: target)
        
        delegate?.wellnessManager(self, didAdvancePhase: newPhase)
    }
    
    private func sendMatePhaseAdvanceNotification(newPhase: Int, newTarget: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🎉 ¡Progreso en Reducción de Mate!"
        
        let newTarget = mateReductionPlan.getCurrentTargetThermos()
        let schedule = mateReductionPlan.getCurrentSchedule().joined(separator: " • ")
        
        content.body = """
        ¡Felicitaciones! Has avanzado a la Fase \(newPhase)
        
        🎯 Nueva meta: \(newTarget) termos por día
        ⏰ Horarios sugeridos: \(schedule)
        
        ¡Seguí así, vas muy bien! 💪
        """
        
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .active
        
        let request = UNNotificationRequest(
            identifier: "mate-phase-advance-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        delegate?.wellnessManager(self, needsNotification: request)
    }
    
    private func scheduleMateReminders() {
        guard isMateTrackingEnabled && isWellnessEnabled else { return }
        
        mateScheduleTimer?.invalidate()
        
        let schedule = mateReductionPlan.getCurrentSchedule()
        let target = mateReductionPlan.getCurrentTargetThermos()
        
        logger.info("🧉 Scheduling mate reminders for \(target) thermos: \(schedule.joined(separator: ", "))")
        
        // Schedule notifications for each time in the schedule
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        mateScheduleTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkMateReminderTime()
        }
    }
    
    private func checkMateReminderTime() {
        guard isMateTrackingEnabled && isWellnessEnabled else { return }
        
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let currentTimeString = formatter.string(from: now)
        
        let schedule = mateReductionPlan.getCurrentSchedule()
        let totalTarget = mateReductionPlan.getCurrentTargetThermos()
        
        for (index, timeString) in schedule.enumerated() {
            if timeString == currentTimeString {
                let thermosNumber = index + 1
                
                sendMateReminderNotification(
                    timeString: timeString,
                    thermosNumber: thermosNumber,
                    totalTarget: totalTarget
                )
                break
            }
        }
    }
    
    private func sendMateReminderNotification(timeString: String, thermosNumber: Int, totalTarget: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🧉 Hora del Mate"
        content.body = "Es hora de tu termo de mate (\(timeString)). Recordá: querés llegar a \(totalTarget) termos hoy."
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "MATE_REMINDER"
        
        let takenAction = UNNotificationAction(
            identifier: "MATE_TAKEN",
            title: "✅ Tomé mi mate",
            options: []
        )
        
        let skipAction = UNNotificationAction(
            identifier: "MATE_SKIP",
            title: "⏭️ Saltar este termo",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "MATE_REMINDER",
            actions: [takenAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "mate-reminder-\(timeString)-\(thermosNumber)",
            content: content,
            trigger: nil
        )
        
        delegate?.wellnessManager(self, needsNotification: request)
        logger.info("🧉 Sent mate reminder for \(timeString)")
    }
    
    // MARK: - Exercise Tracking
    
    func recordExercise(type: String, duration: TimeInterval, intensity: String) {
        guard isExerciseTrackingEnabled && isWellnessEnabled else { return }
        
        logger.info("🏃 Recording exercise: \(type) for \(Int(duration))min")
    }
    
    private func askExerciseQuestion() {
        let content = UNMutableNotificationContent()
        content.title = "🏃‍♂️ Movimiento del Día"
        content.body = "¿Hiciste ejercicio o algún movimiento hoy?\n\n💪 Aunque sea una caminata cuenta"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "EXERCISE_QUESTION"
        
        let yesAction = UNNotificationAction(
            identifier: "EXERCISE_YES",
            title: "✅ Sí, hice ejercicio",
            options: []
        )
        
        let noAction = UNNotificationAction(
            identifier: "EXERCISE_NO", 
            title: "❌ No hice ejercicio",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "EXERCISE_QUESTION",
            actions: [yesAction, noAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "exercise-question-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        delegate?.wellnessManager(self, needsNotification: request)
        logger.info("🏃 Asked exercise question")
    }
    
    // MARK: - Mood Tracking
    
    func recordWellnessCheck(type: String, level: Int, context: String) {
        guard isWellnessEnabled else { return }
        
        // Check if specific tracking is enabled
        switch type {
        case "energy", "stress":
            guard isMoodTrackingEnabled else { return }
        case "mood":
            guard isMoodTrackingEnabled else { return }
        default:
            break
        }
        
        logger.info("😊 Recording wellness check: \(type) level \(level)")
    }
    
    private func askMateQuestion() {
        let content = UNMutableNotificationContent()
        content.title = "🧉 Check-in de Mate"
        content.body = "¿Cuántos mates llevás hoy? ¿Con qué nivel de azúcar?\n\n⏰ Solo toma un segundo responder"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "MATE_QUESTION"
        
        // Add response actions
        let lowAction = UNNotificationAction(
            identifier: "MATE_LOW",
            title: "1-2 mates, sin azúcar",
            options: []
        )
        
        let mediumAction = UNNotificationAction(
            identifier: "MATE_MEDIUM", 
            title: "3-4 mates, poco azúcar",
            options: []
        )
        
        let highAction = UNNotificationAction(
            identifier: "MATE_HIGH",
            title: "5+ mates, con azúcar",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "MATE_QUESTION",
            actions: [lowAction, mediumAction, highAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "mate-question-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        delegate?.wellnessManager(self, needsNotification: request)
        logger.info("🧉 Asked mate question")
    }
    
    private func askMoodQuestion() {
        let content = UNMutableNotificationContent()
        content.title = "😊 Check-in de Energía"
        content.body = "¿Cómo está tu energía en este momento?\n\n⚡ Una respuesta rápida nos ayuda a entender tus patrones"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "MOOD_QUESTION"
        
        let lowAction = UNNotificationAction(
            identifier: "ENERGY_LOW",
            title: "😴 Baja energía",
            options: []
        )
        
        let mediumAction = UNNotificationAction(
            identifier: "ENERGY_MEDIUM",
            title: "😐 Energía normal", 
            options: []
        )
        
        let highAction = UNNotificationAction(
            identifier: "ENERGY_HIGH",
            title: "⚡ Alta energía",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "MOOD_QUESTION",
            actions: [lowAction, mediumAction, highAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "mood-question-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        delegate?.wellnessManager(self, needsNotification: request)
        logger.info("😊 Asked mood question")
    }
    
    // MARK: - Daily Reflection
    
    func saveDailyReflection(mood: String, notes: String) -> DailyReflection {
        guard isDailyReflectionEnabled && isWellnessEnabled else {
            return DailyReflection() // Return empty reflection if disabled
        }
        
        let reflection = DailyReflection(
            dayType: mood,
            journalEntry: notes,
            completedAt: Date()
        )
        
        logger.info("📝 Saved daily reflection: \(mood)")
        delegate?.wellnessManager(self, didSaveDailyReflection: reflection)
        
        return reflection
    }
    
    func askDailyReflection() {
        guard isDailyReflectionEnabled && isWellnessEnabled else { return }
        
        // Check if we haven't asked for reflection today
        let today = Calendar.current.startOfDay(for: Date())
        let hasAskedToday = UserDefaults.standard.object(forKey: "lastReflectionDate") as? Date
        
        if let lastDate = hasAskedToday, Calendar.current.isDate(lastDate, inSameDayAs: today) {
            logger.debug("📝 Already asked for reflection today")
            return
        }
        
        logger.info("📝 Asking for daily reflection")
        
        let content = UNMutableNotificationContent()
        content.title = "📝 Reflexión del Día"
        content.body = "¿Cómo fue tu día de trabajo? Una reflexión rápida te ayuda a cerrar mejor la jornada."
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "DAILY_REFLECTION"
        
        let productiveAction = UNNotificationAction(
            identifier: "REFLECTION_PRODUCTIVE",
            title: "💪 Productivo",
            options: []
        )
        
        let balancedAction = UNNotificationAction(
            identifier: "REFLECTION_BALANCED",
            title: "⚖️ Equilibrado",
            options: []
        )
        
        let tiredAction = UNNotificationAction(
            identifier: "REFLECTION_TIRED",
            title: "😴 Cansado",
            options: []
        )
        
        let stressedAction = UNNotificationAction(
            identifier: "REFLECTION_STRESSED",
            title: "😰 Estresado",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "DAILY_REFLECTION",
            actions: [productiveAction, balancedAction, tiredAction, stressedAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "daily-reflection-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        
        UserDefaults.standard.set(Date(), forKey: "lastReflectionDate")
        delegate?.wellnessManager(self, needsNotification: request)
    }
    
    // MARK: - Persistence
    
    private func saveMateReductionPlan() {
        PersistenceManager.shared.saveMateReductionPlan(mateReductionPlan)
    }
    
    private func loadMateReductionPlan() {
        if let plan = PersistenceManager.shared.loadMateReductionPlan() {
            mateReductionPlan = plan
            logger.info("📖 Loaded mate reduction plan - Phase \(plan.currentPhase)")
        } else {
            mateReductionPlan = MateReductionPlan()
            saveMateReductionPlan()
            logger.info("🆕 Created new mate reduction plan")
        }
    }
    
    // MARK: - Analytics
    
    func generateWellnessStatus() -> (
        mateEnabled: Bool,
        exerciseEnabled: Bool,
        moodEnabled: Bool,
        reflectionEnabled: Bool,
        currentMatePhase: Int,
        mateTarget: Int
    ) {
        return (
            mateEnabled: isMateTrackingEnabled,
            exerciseEnabled: isExerciseTrackingEnabled,
            moodEnabled: isMoodTrackingEnabled,
            reflectionEnabled: isDailyReflectionEnabled,
            currentMatePhase: mateReductionPlan.currentPhase,
            mateTarget: mateReductionPlan.getCurrentTargetThermos()
        )
    }
    
    // MARK: - Testing Support
    
    func triggerTestWellnessQuestions() {
        guard isWellnessEnabled else {
            logger.warning("🚫 Wellness disabled, cannot trigger test questions")
            return
        }
        
        logger.info("🧪 Triggering test wellness questions")
        
        // Schedule test questions with delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.isMateTrackingEnabled {
                self.askMateQuestion()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if self.isExerciseTrackingEnabled {
                self.askExerciseQuestion()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 19) {
            if self.isMoodTrackingEnabled {
                self.askMoodQuestion()
            }
        }
    }
}