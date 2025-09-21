//
//  PersistenceManager.swift
//  FastSwitch
//
//  Created on 2025-09-07.
//

import Foundation
import os.log

// MARK: - PersistenceManager Protocol

protocol PersistenceManagerDelegate: AnyObject {
    func persistenceManager(_ manager: PersistenceManager, didLoadUsageHistory history: UsageHistory)
    func persistenceManager(_ manager: PersistenceManager, didFailWithError error: Error)
}

// MARK: - PersistenceManager

final class PersistenceManager: NSObject {
    
    // MARK: - Singleton
    static let shared = PersistenceManager()
    
    // MARK: - Properties
    weak var delegate: PersistenceManagerDelegate?
    private let logger = Logger(subsystem: "com.bandonea.FastSwitch", category: "PersistenceManager")
    
    // Storage configuration
    private let appSupportURL: URL
    private let dataDirectoryURL: URL
    
    // JSON configuration  
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    // Legacy UserDefaults support
    private let legacyUsageHistoryKey = "FastSwitchUsageHistory"
    private let mateReductionPlanKey = "MateReductionPlan"
    
    // MARK: - Initialization
    
    private override init() {
        // Setup file system paths
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportURL = appSupport.appendingPathComponent("FastSwitch")
        self.dataDirectoryURL = appSupportURL.appendingPathComponent("data")
        
        // Setup JSON encoder/decoder with ISO 8601 dates
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        super.init()
        
        // Create directory structure
        createDataDirectoryIfNeeded()
        
        logger.info("📁 PersistenceManager initialized with data directory: \(self.dataDirectoryURL.path)")
    }
    
    // MARK: - Directory Management
    
    private func createDataDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(
                at: self.dataDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            logger.info("✅ Created data directory: \(self.dataDirectoryURL.path)")
        } catch {
            logger.error("❌ Failed to create data directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Daily File Management
    
    private func fileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return dataDirectoryURL.appendingPathComponent("\(dateString).json")
    }
    
    private func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    // MARK: - Usage History Management
    
    /// Load usage history with migration from UserDefaults
    func loadUsageHistory() -> UsageHistory {
        // First try to load from daily files
        let history = loadFromDailyFiles()
        
        // If no daily files exist, migrate from UserDefaults
        if history.dailyData.isEmpty {
            return migrateFromUserDefaults()
        }
        
        logger.info("📂 Loaded usage history - \(history.dailyData.count) days from daily files")
        return history
    }
    
    private func loadFromDailyFiles() -> UsageHistory {
        var dailyData: [String: DailyUsageData] = [:]
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: dataDirectoryURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }
            
            for fileURL in fileURLs {
                let dateKey = fileURL.deletingPathExtension().lastPathComponent
                
                if let data = try? Data(contentsOf: fileURL),
                   let dayData = try? decoder.decode(DailyUsageData.self, from: data) {
                    dailyData[dateKey] = dayData
                    logger.debug("📖 Loaded data for \(dateKey)")
                } else {
                    logger.warning("⚠️ Failed to decode data for \(dateKey)")
                }
            }
        } catch {
            logger.error("❌ Failed to read daily files: \(error.localizedDescription)")
        }
        
        var history = UsageHistory()
        history.dailyData = dailyData
        return history
    }
    
    private func migrateFromUserDefaults() -> UsageHistory {
        guard let data = UserDefaults.standard.data(forKey: legacyUsageHistoryKey) else {
            logger.info("📂 Starting fresh usage history")
            return UsageHistory()
        }
        
        do {
            let legacyHistory = try decoder.decode(UsageHistory.self, from: data)
            logger.info("🔄 Migrating \(legacyHistory.dailyData.count) days from UserDefaults to daily files")
            
            // Save each day to its own file
            for (dateKey, dayData) in legacyHistory.dailyData {
                saveDailyData(dayData, for: dateKey)
            }
            
            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: legacyUsageHistoryKey)
            logger.info("✅ Migration completed, removed legacy UserDefaults data")
            
            return legacyHistory
        } catch {
            logger.error("❌ Failed to migrate from UserDefaults: \(error.localizedDescription)")
            return UsageHistory()
        }
    }
    
    /// Save daily usage data to individual file
    func saveDailyData(_ data: DailyUsageData, for dateKey: String? = nil) {
        let key = dateKey ?? getTodayKey()
        let fileURL = dataDirectoryURL.appendingPathComponent("\(key).json")
        
        do {
            let encodedData = try encoder.encode(data)
            try encodedData.write(to: fileURL)
            logger.info("💾 Saved daily data for \(key) (\(encodedData.count) bytes)")
        } catch {
            logger.error("❌ Failed to save daily data for \(key): \(error.localizedDescription)")
            delegate?.persistenceManager(self, didFailWithError: error)
        }
    }
    
    /// Get today's usage data
    func getTodayData() -> DailyUsageData? {
        let todayKey = getTodayKey()
        let fileURL = dataDirectoryURL.appendingPathComponent("\(todayKey).json")
        
        guard let data = try? Data(contentsOf: fileURL),
              let dayData = try? decoder.decode(DailyUsageData.self, from: data) else {
            return nil
        }
        
        return dayData
    }
    
    // MARK: - Mate Reduction Plan
    
    func saveMateReductionPlan(_ plan: MateReductionPlan) {
        do {
            let data = try encoder.encode(plan)
            UserDefaults.standard.set(data, forKey: mateReductionPlanKey)
            logger.info("💾 Saved mate reduction plan")
        } catch {
            logger.error("❌ Failed to save mate reduction plan: \(error.localizedDescription)")
        }
    }
    
    func loadMateReductionPlan() -> MateReductionPlan? {
        guard let data = UserDefaults.standard.data(forKey: mateReductionPlanKey) else {
            return nil
        }
        
        do {
            let plan = try decoder.decode(MateReductionPlan.self, from: data)
            logger.info("📖 Loaded mate reduction plan")
            return plan
        } catch {
            logger.error("❌ Failed to load mate reduction plan: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Export Functionality
    
    func exportUsageData() -> URL? {
        let history = loadFromDailyFiles()
        
        // Create export data with schema version
        let exportData: [String: Any] = [
            "schemaVersion": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "dailyData": history.dailyData
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            
            // Save to Desktop
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmm"
            let timestamp = formatter.string(from: Date())
            let exportURL = desktopURL.appendingPathComponent("FastSwitch_export_\(timestamp).json")
            
            try data.write(to: exportURL)
            logger.info("📤 Exported usage data to: \(exportURL.path)")
            return exportURL
            
        } catch {
            logger.error("❌ Failed to export usage data: \(error.localizedDescription)")
            delegate?.persistenceManager(self, didFailWithError: error)
            return nil
        }
    }
    
    // MARK: - Cleanup and Maintenance
    
    /// Remove old daily files (older than specified days)
    func cleanupOldFiles(olderThanDays days: Int = 365) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: dataDirectoryURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }
            
            var removedCount = 0
            for fileURL in fileURLs {
                if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try FileManager.default.removeItem(at: fileURL)
                    removedCount += 1
                }
            }
            
            if removedCount > 0 {
                logger.info("🧹 Cleaned up \(removedCount) old daily files")
            }
        } catch {
            logger.error("❌ Failed to cleanup old files: \(error.localizedDescription)")
        }
    }
    
    /// Get storage statistics
    func getStorageStats() -> (fileCount: Int, totalSizeBytes: Int) {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: dataDirectoryURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }
            
            let totalSize = fileURLs.compactMap { url in
                try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            }.reduce(0, +)
            
            return (fileCount: fileURLs.count, totalSizeBytes: totalSize)
        } catch {
            logger.error("❌ Failed to get storage stats: \(error.localizedDescription)")
            return (fileCount: 0, totalSizeBytes: 0)
        }
    }
}
