//
//  DataModels.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation

// MARK: - Notification Models

enum NotificationMode: Codable {
    case testing, interval45, interval60, interval90, disabled
}

enum WellnessNotificationType: Codable {
    case eyeBreak         // Mirar lejos, descanso visual
    case posturalBreak    // Pararse y estirar
    case hydration        // Tomar agua
    case mate             // Recordatorio de mate
    case exercise         // Ejercicio/movimiento
    case deepBreath       // Respirar profundo
    case workBreak        // Descanso general
    
    var soundName: String {
        switch self {
        case .eyeBreak:      return "Tink.aiff"      // Suave, como parpadeo
        case .posturalBreak: return "Pop.aiff"       // Más dinámico para movimiento
        case .hydration:     return "Drip.aiff"      // Evoca gotas de agua
        case .mate:          return "Glass.aiff"     // Cálido, como termo
        case .exercise:      return "Hero.aiff"      // Motivacional
        case .deepBreath:    return "Blow.aiff"      // Relajante para respiración
        case .workBreak:     return "Submarine.aiff" // General, distintivo
        }
    }
    
    var icon: String {
        switch self {
        case .eyeBreak:      return "👁️"
        case .posturalBreak: return "🧘‍♂️"
        case .hydration:     return "💧"
        case .mate:          return "🧉"
        case .exercise:      return "🏃‍♂️"
        case .deepBreath:    return "🫁"
        case .workBreak:     return "☕"
        }
    }
}

// MARK: - Data Structures for Persistent Storage

struct SessionRecord: Codable {
    let start: Date
    let duration: TimeInterval
}

struct MateRecord: Codable {
    let time: Date
    let thermosCount: Int
    let type: String
    
    // Add schema alignment for analyzer compatibility
    enum CodingKeys: String, CodingKey {
        case time = "timestamp"  // Match analyzer expectations
        case thermosCount = "mateAmount"  // Match analyzer expectations  
        case type
    }
    
    init(time: Date, thermosCount: Int, type: String = "mate") {
        self.time = time
        self.thermosCount = thermosCount
        self.type = type
    }
}

struct ExerciseRecord: Codable {
    let time: Date
    let done: Bool
    let duration: Int // minutes
    let type: String // "walk", "gym", "yoga", "other"
    let intensity: Int // 1-3 (light, moderate, intense)
    
    enum CodingKeys: String, CodingKey {
        case time = "timestamp"  // Match analyzer expectations
        case done, duration, type, intensity
    }
    
    init(time: Date, done: Bool, duration: Int = 0, type: String = "walk", intensity: Int = 1) {
        self.time = time
        self.done = done
        self.duration = duration
        self.type = type
        self.intensity = intensity
    }
}

struct WellnessCheck: Codable {
    let time: Date
    let type: String // "energy", "stress", "mood"
    let level: Int // 1-10 for energy/stress, enum for mood
    let context: String // "morning", "afternoon", "break", "end_day"
    
    enum CodingKeys: String, CodingKey {
        case time = "timestamp"  // Match analyzer expectations
        case type, level, context
    }
    
    init(time: Date, type: String, level: Int, context: String) {
        self.time = time
        self.type = type
        self.level = level
        self.context = context
    }
}

struct DailyReflection: Codable {
    var journalEntry: String
    var dayType: String // "productive", "calm", "burned_out", "anxious", "sick", "inspired"
    var lessonsLearned: String
    var phraseOfTheDay: String
    var completedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case journalEntry, dayType, lessonsLearned, phraseOfTheDay
        case completedAt = "timestamp"  // Match analyzer expectations
    }
    
    init() {
        self.journalEntry = ""
        self.dayType = ""
        self.lessonsLearned = ""
        self.phraseOfTheDay = ""
        self.completedAt = nil
    }
}

struct WellnessMetrics: Codable {
    var mateRecords: [MateRecord]
    var exerciseRecords: [ExerciseRecord]
    var energyLevels: [WellnessCheck]
    var stressLevels: [WellnessCheck]
    var moodChecks: [WellnessCheck]
    
    // Schema alignment for analyzer compatibility
    enum CodingKeys: String, CodingKey {
        case mateRecords = "mateAndSugarRecords"  // Match analyzer expectations
        case exerciseRecords, energyLevels, stressLevels, moodChecks
    }
    
    init() {
        self.mateRecords = []
        self.exerciseRecords = []
        self.energyLevels = []
        self.stressLevels = []
        self.moodChecks = []
    }
}

struct DailyUsageData: Codable {
    let date: Date
    var totalSessionTime: TimeInterval
    var appUsage: [String: TimeInterval]
    var breaksTaken: [SessionRecord]
    var continuousWorkSessions: [SessionRecord]
    var deepFocusSessions: [SessionRecord]
    var longestContinuousSession: TimeInterval
    var totalBreakTime: TimeInterval
    var callTime: TimeInterval
    
    // New wellness data
    var wellnessMetrics: WellnessMetrics
    var dailyReflection: DailyReflection
    var workdayStart: Date?
    var workdayEnd: Date?
    
    init(date: Date) {
        self.date = date
        self.totalSessionTime = 0
        self.appUsage = [:]
        self.breaksTaken = []
        self.continuousWorkSessions = []
        self.deepFocusSessions = []
        self.longestContinuousSession = 0
        self.totalBreakTime = 0
        self.callTime = 0
        
        // Initialize wellness data
        self.wellnessMetrics = WellnessMetrics()
        self.dailyReflection = DailyReflection()
        self.workdayStart = nil
        self.workdayEnd = nil
    }
}

struct UsageHistory: Codable {
    var dailyData: [String: DailyUsageData]
    
    // Add schema versioning for future migration
    let schemaVersion: String
    
    enum CodingKeys: String, CodingKey {
        case dailyData, schemaVersion
    }
    
    init() {
        self.dailyData = [:]
        self.schemaVersion = "1.0"
    }
    
    // Custom decoder to handle backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailyData = try container.decode([String: DailyUsageData].self, forKey: .dailyData)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "0.9"
    }
}

struct MateReductionPlan: Codable {
    let startDate: Date
    var currentPhase: Int
    let targetThermos: [Int] // 5, 4, 3, 2
    let phaseDuration: Int // days per phase
    let schedules: [[String]] // scheduled times for each phase
    
    init() {
        self.startDate = Date()
        self.currentPhase = 0
        self.targetThermos = [5, 4, 3, 2]
        self.phaseDuration = 3
        self.schedules = [
            ["08:00", "10:30", "13:00", "15:30", "17:30"], // Phase 0: 5 termos
            ["08:00", "11:00", "14:00", "16:30"],           // Phase 1: 4 termos
            ["08:30", "13:00", "16:00"],                    // Phase 2: 3 termos
            ["09:00", "15:30"]                              // Phase 3: 2 termos
        ]
    }
    
    func getCurrentTargetThermos() -> Int {
        guard currentPhase < targetThermos.count else { return 2 }
        return targetThermos[currentPhase]
    }
    
    func getCurrentSchedule() -> [String] {
        guard currentPhase < schedules.count else { return ["09:00", "15:30"] }
        return schedules[currentPhase]
    }
    
    func shouldAdvancePhase() -> Bool {
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        let expectedPhase = daysSinceStart / phaseDuration
        return expectedPhase > currentPhase && currentPhase < 3
    }
}

struct MotivationalPhrase: Codable {
    let id: String
    let category: String
    let text: String
    let contexts: [String]
    let weight: Double
}

struct PhrasesData: Codable {
    let phrases: [MotivationalPhrase]
}