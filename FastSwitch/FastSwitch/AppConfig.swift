import Foundation

enum AppConfig {
    // Global feature flags (UserDefaults-backed)
    static var wallpaperEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "WallpaperEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "WallpaperEnabled") }
    }

    static var wellnessDefaultEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "WellnessEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "WellnessEnabled") }
    }

    static var enableTestingHelpers: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
