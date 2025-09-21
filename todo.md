# FastSwitch — TODO

Status legend: [ ] pending, [~] in progress, [x] done

1) Manager migration (slim AppDelegate)
- [x] Route Deep Focus UI/actions through `DeepFocusManager`
- [x] Move wellness question scheduling fully to `WellnessManager`
- [x] Move break reminder notifications fully to `BreakReminderManager`
- [ ] Remove/deprecate legacy Deep Focus methods in `AppDelegate`

2) Align wellness export schema with analyzer
- [x] Update `usage_analyzer.py` to support current app schema:
  - Accept `wellnessMetrics.energyLevels` in addition to `energyChecks`
  - Read `dailyReflection` from top-level and map `dayType` → `mood`
  - Tolerate missing `energyLevel`, `stressLevel`, `workQuality`
- [ ] (Alternative) If desired later: adjust app export to analyzer’s schema

3) Remove absolute paths; use standard locations
- [x] Load `phrases.json` from Bundle or `~/Library/Application Support/FastSwitch/phrases.json`
- [ ] Add Preferences to select a custom phrases file

4) Production defaults and testing gates
- [ ] Default notification mode to 60–90m outside DEBUG
- [ ] Gate all testing timers/hooks behind `#if DEBUG`

5) Centralize configuration
- [ ] Add `AppConfig.swift` with feature flags (wallpaper, wellness defaults, testing)
- [ ] Remove duplicated `DISABLE_WALLPAPER`/`WALLPAPER_KILL_SWITCH`

6) Logging consistency
- [ ] Replace remaining `print` with `Logger`

7) Preferences UI
- [ ] SwiftUI Preferences: General, Focus, Wellness, Notifications, Phrases, Displays

8) Dasung/Paperlike robustness
- [ ] Make known UUIDs configurable; add “Detect” button
- [ ] Expose rotation hop + DDC index in Preferences

9) scripts/clean.sh
- [ ] Implement cleanup steps from README (idempotent)

10) Internationalization
- [ ] Extract strings to `Localizable.strings` (es/en)

11) Tests and CI
- [ ] Unit tests for managers (usage, persistence, wellness)
- [ ] GitHub Actions: macOS build + tests

12) Docs polish
- [ ] README: format install/reset blocks; add brief privacy note
