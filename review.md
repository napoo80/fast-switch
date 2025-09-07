**FastSwitch — Technical & Product Review**

- Repo snapshot: SwiftUI macOS menu bar app with Carbon hotkeys, AppleScript automations, wellness/usage tracking, DASUNG e‑ink helpers, and a Python usage analyzer.
- Key files: `FastSwitch/FastSwitch/AppDelegate.swift` (very large, multi‑domain), `DasungRefresher.swift`, `DasungDDC.swift`, `WallpaperPhraseManager.swift`, `NSScreen+IDs.swift`, tests scaffolding, `usage_analyzer.py`, docs.
- Note: The refactor plan file is `refactor.md` (not refartor.md).

**Executive Summary**
- Strong foundation with a clear “instant app switching” core and thoughtful wellness/analytics features. However, the current architecture centralizes too many responsibilities in `AppDelegate.swift`, leading to maintainability and testability issues.
- The Python analyzer and the Swift persistence schema are out of sync (key names, structures, and date encoding), which will break analytics unless aligned.
- Product-wise, defaults are developer-centric; a basic Preferences UI and onboarding would lift UX greatly. Internationalization and clearer privacy messaging are important if sharing beyond your own machine.

**Technical Findings**
- Architecture & Code Organization
  - `AppDelegate.swift` mixes 10+ domains (hotkeys, usage tracking, notifications, deep focus, wellness, DASUNG, wallpaper, export, menu UI…). This violates SRP and complicates changes, debugging, and tests.
  - You already extracted focused helpers (e.g., `DasungRefresher`, `DasungDDC`, `WallpaperPhraseManager`, `NSScreen+IDs`). Extending this pattern across the rest of the domains will meaningfully simplify the codebase.
  - Many AppleScript automation blocks are brittle (UI scripting System Settings, Slack). Expect OS/app version drift to break flows; consider fallback paths and capability checks.

- Persistence & Data Model
  - JSON schema mismatch vs analyzer:
    - Swift uses `WellnessMetrics { mateRecords, exerciseRecords, energyLevels, stressLevels, moodChecks }` and top-level `dailyReflection` in each day; Python expects `wellnessMetrics` containing `mateAndSugarRecords`, `exerciseRecords`, `energyChecks`, and `dailyReflection` inside wellness.
    - Field name mismatches: analyzer expects `timestamp`, `mateAmount`, `sugarLevel`; Swift uses `time`, `thermosCount`, and no sugar metric field.
  - Date encoding: Swift `JSONEncoder` default encodes `Date` as numeric; analyzer assumes ISO 8601 strings. Set `JSONEncoder.dateEncodingStrategy = .iso8601` and `JSONDecoder.dateDecodingStrategy = .iso8601` (and update existing data or support legacy decoding).
  - Consider adding `schemaVersion` in the exported JSON. Provide a compatibility exporter (v1 vs v2) or a migration layer in the analyzer.
  - `UserDefaults` for all usage history will grow and is not ideal for larger datasets. Suggest on-disk JSON (by day) or a lightweight store (e.g., one file per day or SQLite/CoreData). Keep `UserDefaults` for settings only.

- Notifications & Timers
  - Multiple timers (usage, dashboard, focus, wellness) run on the main runloop. Good use of `[weak self]` in most places; verify all timers are invalidated on teardown toggles to avoid leaks.
  - You rely heavily on notifications as UI; banner overload is possible. Consider grouping or rate limiting; use `interruptionLevel` judiciously.
  - Ensure notification category registration happens before requests and is idempotent.

- Hotkeys & Shortcuts
  - Carbon hotkeys are fine for macOS; mapping is hard-coded. Suggest a simple Preferences UI to edit bundle IDs and shortcut behaviors, with validation and a “Detect bundle ID…” helper.
  - App-specific double‑tap actions are helpful; add a per‑app configuration surface.

- External Tools (ddcctl, displayplacer, m1ddc)
  - Nice fallbacks in `DasungRefresher` if tools aren’t found. Expose detection status + quick test actions in a submenu.
  - The `displayplacer` profiles are hard-coded with Spanish identifiers (`ochocientosPorSeiscientos` etc.). Rename to English and let users configure per-display profiles.

- AppleScript Integrations
  - Toggling Slack DND via UI scripting is fragile. Prefer Slack AppleScript dictionary/API where possible; otherwise wrap with robust existence/timeouts and silent failures.
  - System Settings UI scripting to change ICC profile will be brittle across OS updates; label this experimental and keep a safe fallback.

- Code Quality & Style
  - Mix of English/Spanish identifiers and logs; good for local dev, but standardize for collaborators or add i18n.
  - Many print logs; consider `OSLog` with categories and log levels. Provide a “Debug logging” toggle.
  - Centralize constants (keys, sound names, category IDs) and reuse enums for tags/IDs.

- Testing & CI
  - Tests are placeholders. After refactor into managers, add unit tests where boundaries are clear (hotkeys routing, persistence encode/decode, usage session accounting, notification scheduling decisions). Keep UI tests thin.
  - Add a simple GitHub Actions workflow (build + unit tests) if you plan to share/collab.

- Security & Privacy
  - Clear privacy posture is needed: all data appears local; say so explicitly in README and first‑run. Provide: disable analytics, delete data, and export.
  - Align bundle identifiers in docs: README uses `Bandonea.FastSwitch` in defaults/tccutil, while Info.plist uses `$(PRODUCT_BUNDLE_IDENTIFIER)`. Pick one (e.g., `com.bandonea.FastSwitch`) and update docs/scripts consistently.

- Distribution
  - README suggests copying Debug builds. If you plan to share, add an Ad‑Hoc/Developer ID signed “Release” and optional notarization notes. If App Store is a goal, plan entitlements/sandbox impacts (Apple Events, etc.).

**Analyzer Alignment (Critical)**
- Current analyzer expects:
  - `dailyData: { "YYYY-MM-DD": { ... } }`
  - Inside each day:
    - `totalSessionTime`, `totalBreakTime`, `callTime`, `deepFocusSessions`, `continuousWorkSessions`, `appUsage`.
    - `wellnessMetrics` object including `mateAndSugarRecords` (with `timestamp`, `mateAmount`, `sugarLevel`), `exerciseRecords` (with `done`, `duration`, `type`), and `energyChecks` (with `energyLevel`).
    - `dailyReflection` under wellness.
- Swift currently stores:
  - `DailyUsageData` with `wellnessMetrics { mateRecords, exerciseRecords, energyLevels, stressLevels, moodChecks }` and `dailyReflection` at the day root.
- Fix options:
  - Change Swift model names to match analyzer (preferred), add missing fields (e.g., sugar), and move `dailyReflection` inside `wellnessMetrics`. Set JSON encoder to ISO 8601. Or…
  - Update `usage_analyzer.py` to match the current Swift schema (rename keys, ignore missing sugar for now, accept numeric dates). Given the analyzer is documented as part of the product, aligning the app’s exported JSON to the docs is cleaner.

**Product Findings**
- Onboarding & Permissions
  - First-run should show a small walkthrough: why Accessibility/Automation/Notifications are needed, how to enable “Use F1, F2… as standard function keys”, and how to customize mappings.

- Preferences
  - Add a “Preferences” window with:
    - F‑key → app mapping editor (add/remove rows, detect bundle ID from running apps).
    - Notification intervals (45/60/90), Deep Focus default duration, toggle wellness questions, dashboard time.
    - DASUNG settings (enable rotation hop, display UUID selection, test buttons).
    - Language (English/Spanish), logging level, and data controls (export/delete).

- Wellness System
  - Great ideas (mate reduction, exercise, energy checks) but make it opt‑in per category. For non‑mate users, generalize to “caffeine” or “hydration only”.
  - Limit notification frequency and provide a “quiet hours” schedule.

- UX & Feedback
  - Notifications carry a lot of UI. Consider a lightweight popover for dashboard/reflection to reduce cognitive load.
  - Use consistent language and tone; add i18n for strings.

- Reports & Insights
  - Daily/weekly/yearly reports delivered as notifications are clever; add a “Reports…” menu item that opens a popover/window with the same info and export controls.
  - Provide basic charts (even ASCII/monospace in a popover), and a “copy to clipboard” option.

- Documentation
  - README mixes English and Spanish and includes local paths; streamline and separate developer vs user docs. Fix bundle ID references; consolidate reset steps into a script (the included `scripts/clean.sh` is empty).

**Refactor Plan Review (refactor.md)**
- Strengths
  - Clear problem statement and domains identified; good modular target (Managers/Coordinators/Models) and incremental commits. Success metrics are concrete.
  - Aligns with `DasungDDC`/`DasungRefresher` separation already in code.

- Gaps & Risks
  - Data migration not detailed: moving model files and changing coding keys will affect decoding previous `UserDefaults` blobs. Add a migration plan (schema version, graceful decode with both old/new keys).
  - Analyzer/schema alignment not called out; add a task to unify keys + date strategy and update docs.
  - Coordinators sound good; consider whether you really need both, or if a single “AppCoordinator” with feature sub‑managers is enough to avoid orchestration creep.
  - Dependency injection: spell out how managers obtain dependencies (protocols + simple container), and keep side‑effects out of initializers to simplify tests.

- Suggested Adjustments
  - Phase 1: Extract Models with explicit `CodingKeys` matching analyzer (or vice versa), set `JSONEncoder/Decoder` to ISO 8601, add `schemaVersion`.
  - Phase 2: Extract `NotificationCenter` wrapper first (NotificationManager) because many managers depend on it; then Hotkey/AppSwitching; then Usage/Breaks.
  - Phase 3: PersistenceManager writes one JSON per day under `~/Library/Application Support/FastSwitch/data/2025-09-07.json` to avoid large blobs in `UserDefaults`.
  - Phase 4: MenuBarManager builds the NSMenu and exposes minimal update methods; all strings via a Strings file for i18n.
  - Testing: Add unit tests as each manager is extracted. Start with encode/decode tests for models, then usage timing edge cases.

**Quick Wins (High ROI)**
- Set `JSONEncoder/Decoder` to ISO 8601; add `CodingKeys` aligning with analyzer; add `schemaVersion`.
- Fix bundle ID references in README, scripts, and code examples (choose `com.bandonea.FastSwitch`).
- Add a minimal Preferences window for F‑key mapping and notification mode.
- Rename Spanish code identifiers within code to English (public API, constants) for consistency; keep localized user-facing strings.
- Add a “Disable Wellness” master toggle and default it off for new users.
- Replace print logs with `OSLog` categories; add a debug logging toggle.
- Fill `scripts/clean.sh` with the reset steps currently embedded in README.

**Next Steps (Proposed Order)**
- Week 1
  - Align exported JSON schema + date strategy; update analyzer accordingly; write a short “Data Schema” doc.
  - Extract Models + NotificationManager; add unit tests for encode/decode and notification category setup.
  - Preferences window: mapping + intervals; persist settings separately from usage data.
- Week 2
  - Extract HotkeyManager and AppSwitchingManager; keep behavior identical; unit test routing logic.
  - Extract UsageTrackingManager + BreakReminderManager; add tests for idle thresholds + intervals.
- Week 3
  - Extract WellnessManager; gate features behind prefs; add i18n groundwork.
  - Slim AppDelegate to setup + DI; add CI workflow for build/tests.

**Notable Issues to Track**
- Analyzer vs app schema mismatch (blocking analytics).
- Empty `scripts/clean.sh` vs detailed reset steps in README.
- Mixed languages in code and docs; fix bundle ID references everywhere.
- Reliance on brittle AppleScript UI scripting; ensure fallbacks and safe failures.

If you want, I can: (a) align the exported JSON schema + analyzer, (b) scaffold the Preferences UI for mappings/notifications, or (c) start the refactor by extracting Models and NotificationManager.

