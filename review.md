# FastSwitch — Codebase Review and Implementation Plan

## Summary

FastSwitch is a macOS menu bar app for instant app switching via F‑keys, with added ergonomics: usage tracking, break reminders, Deep Focus, wellness prompts, motivational phrases, and optional e‑ink monitor helpers (Dasung/Paperlike). The project recently introduced a modular manager architecture (NotificationManager, HotkeyManager, AppSwitchingManager, PersistenceManager, UsageTrackingManager, BreakReminderManager, WellnessManager, MenuBarManager, DeepFocusManager) but AppDelegate still holds significant legacy logic, leading to duplication and mixed responsibilities. Documentation is good and includes testing guides and a Python usage analyzer.

## Current Status (high level)

- Architecture
  - Managers exist for major domains; singletons with delegate protocols and os.Logger.
  - AppDelegate wires everything, but also re‑implements logic that belongs in managers (Deep Focus, wellness questions, sticky notifications, mate plan, etc.).
  - Menu bar is feature‑rich and configurable; wallpaper phrases feature is conditionally disabled.
- Persistence
  - Daily JSON files in Application Support (good). Legacy UserDefaults migration supported.
  - CodingKeys partially aligned to analyzer schema (mate records), but not fully (see gaps below).
- Tooling
  - Xcode project; minimal unit/UI tests; no CI; no SwiftLint/SwiftFormat config.
- External deps
  - Uses AppleScript automation; optional Homebrew tools (m1ddc, displayplacer, ddcctl).
- Docs
  - README, TESTING_GUIDE, QUICK_TEST_SETUP, USAGE_ANALYZER are detailed and helpful.

## Key Findings & Suggestions

- Responsibility duplication in AppDelegate
  - Several workflows (Deep Focus, wellness prompts, break reminders, notifications) are implemented in both AppDelegate and their respective managers. This increases complexity and risk of drift.
  - Suggestion: finish the migration. AppDelegate should primarily coordinate managers and react to delegates; business logic and timers should live inside managers.

- Analyzer schema mismatch (wellness)
  - Analyzer expects: `wellnessMetrics.energyChecks` and `dailyReflection` fields like `mood`, `energyLevel`, `stressLevel`, `workQuality`.
  - App exports: `energyLevels` (not `energyChecks`) and `DailyReflection` with `dayType`, `journalEntry`, etc.
  - Suggestion: either (a) adapt app export keys to the analyzer’s expected schema, or (b) update the analyzer to read the app’s schema. Pick one and make both sides consistent.

- Hardcoded paths and machine‑specific values
  - `AppDelegate.loadPhrasesFromFile` tries an absolute path `/Users/gaston/.../phrases.json`.
  - Dasung UUIDs are hardcoded; user‑specific.
  - Suggestion: remove absolute paths. Load phrases from the app bundle (Resource) and/or from `~/Library/Application Support/FastSwitch/phrases.json`. Make Dasung UUIDs configurable via preferences or a plist.

- Testing defaults leak into production
  - Default `NotificationMode` is `.testing` and several testing timers are enabled by default via `setNotificationIntervalTest()` and DEBUG hooks.
  - Suggestion: gate testing helpers behind `#if DEBUG` and ensure production defaults use reasonable intervals (e.g., 60–90 min).

- Inconsistent logging
  - Mix of `print` and `Logger`.
  - Suggestion: standardize on os.Logger across the codebase.

- Internationalization and copy
  - Mixed Spanish/English strings in menus, logs, and notifications.
  - Suggestion: introduce `Localizable.strings` and choose a default locale; keep English/Spanish variants as needed.

- Entitlements and permissions
  - Info.plist contains NSAppleEventsUsageDescription (good). Entitlements file is empty.
  - Suggestion: verify if the app needs additional entitlements (hardened runtime, incoming/outgoing connections not needed now). Keep Accessibility as TCC prompt only (correct today). Ensure Notification permission request flows through NotificationManager (already in place).

- Preferences surface
  - Many features are only toggled via code or hidden menu switches (e.g., wellness enable/disable, mate tracking, Deep Focus duration, wallpaper phrases, Dasung behavior).
  - Suggestion: add a small Preferences window (SwiftUI) to manage feature flags, intervals, phrase source, Dasung settings.

- Scripts and operations
  - `scripts/clean.sh` is empty; README contains manual cleanup steps.
  - Suggestion: implement `scripts/clean.sh` with those steps to streamline resets.

- Tests and CI
  - Tests are placeholder only. No CI.
  - Suggestion: add lightweight unit tests for managers (pure logic), and a GitHub Actions workflow to build/test on macOS runner.

- Wallpaper feature flags
  - Duplicate constants (`DISABLE_WALLPAPER`, `WALLPAPER_KILL_SWITCH`) across files.
  - Suggestion: centralize feature flags in a single config (e.g., `AppConfig.swift`) and reflect state in menu.

## Proposed TODO (prioritized)

1) Complete manager migration, slim AppDelegate
- Remove duplicated wellness, Deep Focus, and break logic from AppDelegate.
- Route all scheduling and notification creation through the relevant managers.
- Keep AppDelegate as orchestrator: set delegates, handle menu actions, persist high‑level state.

2) Align wellness export schema with analyzer
- Option A (recommended): Update app’s CodingKeys/structures to export:
  - `wellnessMetrics.energyChecks` instead of `energyLevels`.
  - Extend `DailyReflection` to include `mood`, `energyLevel`, `stressLevel`, `workQuality` fields used by the analyzer.
- Option B: Update `usage_analyzer.py` to read current app keys: `energyLevels` and `dailyReflection.dayType` etc., mapping to the expected semantics.

3) Remove absolute paths; use standard locations
- Phrases: load from Bundle resource if present; otherwise from `~/.fast-switch/phrases.json`.
- Add a Preferences control to choose a custom phrases file.

4) Production defaults and testing gates
- Default `NotificationMode` to `.interval60` (or `.interval90`).
- Wrap testing timers and `startWellnessTestingMode()` behind `#if DEBUG` with a single toggle.

5) Centralize configuration
- Add `AppConfig.swift` with feature flags (wallpaper, wellness default on/off, testing mode availability).
- Replace duplicate constants (`DISABLE_WALLPAPER`, `WALLPAPER_KILL_SWITCH`) with a single source of truth.

6) Logging standardization
- Replace `print` with structured `Logger` in AppDelegate and other files for consistency.

7) Preferences UI (SwiftUI)
- Tabs: General (F‑key mappings read‑only link), Focus (durations), Wellness (enable, sub‑features, intervals), Notifications (interval presets), Phrases (source), Displays (Dasung UUID/strategy).
- Persist via UserDefaults.

8) Dasung/Paperlike robustness
- Make known UUIDs a user‑editable list; add a “Detect” button that logs available display UUIDs.
- Expose “Use rotation hop” toggle and DDC index in Preferences.

9) scripts/clean.sh
- Implement cleanup script mirroring README “Limpieza completa” steps safely (idempotent, with checks).

10) Internationalization
- Extract user‑facing strings into `Localizable.strings` (es, en). Keep logs in English, or gate by locale.

11) Tests and CI (incremental)
- Add unit tests for: `UsageTrackingManager` session math, `PersistenceManager` round‑trip encode/decode, `WellnessManager` schedule progression.
- Add GitHub Actions macOS workflow: build + test.

12) Documentation polish
- Update README “Reset permissions” and “Pre‑installed apps” as code blocks.
- Add a small “Privacy” note describing local‑only data storage and export behavior.

## Concrete Implementation Notes

- Phrases loading
  - Bundle: `Bundle.main.url(forResource: "phrases", withExtension: "json")`
  - App configs: `~/.fast-switch/phrases.json` (create folder if missing).

- Wellness schema
  - If changing app side, extend `DailyReflection` to map analyzer fields, e.g.:
    - `mood` (map from `dayType`), `energyLevel` (optional numeric), `stressLevel` (optional numeric), `workQuality` (derive from mood or add new user input).
  - Or, change analyzer to use existing keys: `energyLevels` list and `dailyReflection.dayType`.

- AppDelegate simplification
  - Replace direct UNNotification code with calls into NotificationManager.
  - Remove timers and sticky notification loops now owned by managers.
  - Keep delegate implementations to route user actions and persist via PersistenceManager.

- Feature flags
  - Introduce `AppConfig.swift` with static lets or computed properties backed by UserDefaults.

## Risks / Considerations

- AppleScript automation and Accessibility need clear permission flows; ensure first‑run UX is smooth.
- m1ddc/displayplacer availability varies; guards are present, but expose options in Preferences and surface errors via notifications.
- Changing wellness schema may invalidate older exports; consider versioning in exported JSON (`schemaVersion`) and documenting changes.

## Quick Wins (this week)

- Remove absolute phrases path; fall back to Bundle/AppSupport.
- Default NotificationMode to `.interval60` outside DEBUG.
- Replace remaining `print` calls in managers/AppDelegate with `Logger`.
- Implement `scripts/clean.sh` based on README steps.
- Update analyzer or app schema for `energyChecks` vs `energyLevels` to unlock wellness insights.

