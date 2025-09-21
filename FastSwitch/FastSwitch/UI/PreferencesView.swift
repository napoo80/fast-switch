import SwiftUI

struct PreferencesView: View {
    // Wellness toggles (must match keys in WellnessManager)
    @AppStorage("WellnessEnabled") private var wellnessEnabled: Bool = AppConfig.wellnessDefaultEnabled
    @AppStorage("WellnessMateTrackingEnabled") private var mateEnabled: Bool = false
    @AppStorage("WellnessExerciseTrackingEnabled") private var exerciseEnabled: Bool = false
    @AppStorage("WellnessMoodTrackingEnabled") private var moodEnabled: Bool = false
    @AppStorage("WellnessDailyReflectionEnabled") private var reflectionEnabled: Bool = false

    // Wallpaper phrases
    @AppStorage("WallpaperEnabled") private var wallpaperEnabled: Bool = AppConfig.wallpaperEnabled

    // Deep Focus default duration (seconds)
    @AppStorage("DeepFocusDuration") private var deepFocusDuration: Double = 3600

    @AppStorage("PhrasesPath") private var phrasesPath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Text("Wellness")) {
                Toggle("Enable Wellness", isOn: $wellnessEnabled)
                Toggle("Mate Tracking", isOn: $mateEnabled)
                Toggle("Exercise Tracking", isOn: $exerciseEnabled)
                Toggle("Mood Checks", isOn: $moodEnabled)
                Toggle("Daily Reflection", isOn: $reflectionEnabled)
            }

            GroupBox(label: Text("Deep Focus")) {
                Picker("Default Duration", selection: $deepFocusDuration) {
                    Text("45 minutes").tag(2700.0)
                    Text("60 minutes").tag(3600.0)
                    Text("90 minutes").tag(5400.0)
                }.pickerStyle(.segmented)
            }

            GroupBox(label: Text("Wallpaper Phrases")) {
                Toggle("Enable Wallpaper Phrases", isOn: $wallpaperEnabled)
                Text("Shows motivational phrases on desktop wallpaper when enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
                HStack {
                    Text("Phrases JSON Path")
                    TextField("/path/to/phrases.json", text: $phrasesPath)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Spacer()
                    Button("Reload Phrases") {
                        if let app = NSApp.delegate as? AppDelegate {
                            app.reloadMotivationalPhrases()
                        }
                    }
                }
            }

            Spacer(minLength: 8)
            Text("Changes take effect immediately.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: wellnessEnabled) { _, new in
            WellnessManager.shared.setWellnessEnabled(new)
        }
        .onChange(of: mateEnabled) { _, new in WellnessManager.shared.setMateTrackingEnabled(new) }
        .onChange(of: exerciseEnabled) { _, new in WellnessManager.shared.setExerciseTrackingEnabled(new) }
        .onChange(of: moodEnabled) { _, new in WellnessManager.shared.setMoodTrackingEnabled(new) }
        .onChange(of: reflectionEnabled) { _, new in WellnessManager.shared.setDailyReflectionEnabled(new) }
        .onChange(of: deepFocusDuration) { _, new in DeepFocusManager.shared.setCustomDuration(new) }
        .onChange(of: wallpaperEnabled) { _, new in
            AppConfig.wallpaperEnabled = new
            if new {
                WallpaperPhraseManager.shared.start()
            } else {
                WallpaperPhraseManager.shared.stop()
            }
        }
    }
}

#Preview {
    PreferencesView()
}
