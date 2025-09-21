import Testing
@testable import FastSwitch

struct AppConfigTests {
    @Test func wallpaperFlagPersists() async throws {
        AppConfig.wallpaperEnabled = false
        #expect(AppConfig.wallpaperEnabled == false)
        AppConfig.wallpaperEnabled = true
        #expect(AppConfig.wallpaperEnabled == true)
        AppConfig.wallpaperEnabled = false
        #expect(AppConfig.wallpaperEnabled == false)
    }

    @Test func wellnessFlagPersists() async throws {
        AppConfig.wellnessDefaultEnabled = false
        #expect(AppConfig.wellnessDefaultEnabled == false)
        AppConfig.wellnessDefaultEnabled = true
        #expect(AppConfig.wellnessDefaultEnabled == true)
    }

    @Test func deepFocusDurationDefaultCanChange() async throws {
        let defaults = UserDefaults.standard
        defaults.set(3600.0, forKey: "DeepFocusDuration")
        #expect(defaults.double(forKey: "DeepFocusDuration") == 3600.0)
        defaults.set(2700.0, forKey: "DeepFocusDuration")
        #expect(defaults.double(forKey: "DeepFocusDuration") == 2700.0)
    }
}

