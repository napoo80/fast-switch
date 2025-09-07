# AppDelegate Refactoring Plan

## Problem Statement
The AppDelegate.swift file has grown to **4270 lines** and violates the Single Responsibility Principle by handling multiple unrelated concerns. This creates maintenance issues, makes testing difficult, and reduces code readability.

## Current State Analysis

### AppDelegate Responsibilities (13 different domains):
1. **Global Hotkey Management** - F-key registration and handling via Carbon
2. **App Switching Logic** - Bundle ID mapping and app activation
3. **Usage Tracking System** - Session monitoring, app usage analytics
4. **Break Timer System** - Reminders and notifications
5. **Wellness Tracking** - Mate consumption, exercise, mood tracking
6. **Deep Focus Mode** - Concentration sessions management  
7. **Notification Management** - UNUserNotificationCenter delegate
8. **Data Persistence** - Saving/loading usage history, wellness metrics
9. **Dashboard/Reporting** - Daily summaries and analytics
10. **Meet Integration** - Google Meet microphone/camera controls
11. **Dasung Monitor Controls** - Display refresh and resolution switching
12. **Wallpaper Management** - Motivational phrases system
13. **Menu Bar UI** - Status item and menu management

### Key Issues:
- **Massive file size** - 4270 lines is unmaintainable
- **Mixed concerns** - Hotkey handling mixed with wellness tracking
- **Testing difficulty** - Cannot isolate individual features
- **Code reuse** - Cannot reuse components independently
- **Debugging complexity** - Hard to trace issues across domains

## Refactoring Strategy

### Design Principles
- **Single Responsibility** - Each class handles one domain
- **Dependency Injection** - Clean interfaces between components
- **Modular Architecture** - Following DasungDDC pattern (already in codebase)
- **Preserve Behavior** - No functional changes, only structural
- **Incremental Migration** - Extract one system at a time

### Target Architecture

```
AppDelegate (Slim coordinator)
├── Managers/ (Business logic)
│   ├── HotkeyManager
│   ├── AppSwitchingManager  
│   ├── UsageTrackingManager
│   ├── BreakReminderManager
│   ├── WellnessManager
│   ├── NotificationManager
│   ├── PersistenceManager
│   └── MenuBarManager
├── Coordinators/ (Orchestration)
│   ├── WellnessCoordinator
│   └── ProductivityCoordinator
└── Models/ (Data structures)
    ├── SessionModels.swift
    ├── WellnessModels.swift
    ├── UsageModels.swift
    └── NotificationModels.swift
```

## Detailed Implementation Plan

### Phase 1: Foundation Setup

#### 1.1 Create Folder Structure
```
FastSwitch/
├── Models/
├── Managers/ 
└── Coordinators/
```

#### 1.2 Extract Domain Models
Move all `Codable` structs from AppDelegate to dedicated files:

**SessionModels.swift**
- `SessionRecord`
- `MateRecord` 
- `ExerciseRecord`

**WellnessModels.swift**
- `WellnessCheck`
- `DailyReflection`
- `WellnessMetrics`
- `MateReductionPlan`

**UsageModels.swift**
- `DailyUsageData`
- `UsageHistory`

**NotificationModels.swift**
- `NotificationMode` enum
- `WellnessNotificationType` enum
- `MotivationalPhrase`
- `PhrasesData`

### Phase 2: Extract Core Managers

#### 2.1 HotkeyManager.swift
**Responsibility**: Global hotkey registration and event routing
**Key Components**:
- Carbon event handler registration
- F-key to action mapping
- Double-tap detection logic
- Event routing to appropriate managers

**Interface**:
```swift
protocol HotkeyManagerProtocol {
    func registerHotkeys()
    func handleKeyPress(_ keyCode: UInt32)
    var delegate: HotkeyManagerDelegate? { get set }
}

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManager(_ manager: HotkeyManager, didReceiveAction action: String)
    func hotkeyManager(_ manager: HotkeyManager, didReceiveDoubleAction action: String)
}
```

#### 2.2 AppSwitchingManager.swift
**Responsibility**: App activation and bundle ID management
**Key Components**:
- Bundle ID to app mapping
- App activation via NSWorkspace
- Permission handling for app automation

**Interface**:
```swift
protocol AppSwitchingManagerProtocol {
    func activateApp(bundleId: String)
    func sendKeystroke(to bundleId: String, keystroke: String)
    var appMapping: [UInt32: String] { get }
}
```

#### 2.3 UsageTrackingManager.swift
**Responsibility**: Session monitoring and app usage analytics
**Key Components**:
- CGEventSource activity detection
- Session time tracking
- App usage monitoring
- Call detection logic

**Interface**:
```swift
protocol UsageTrackingManagerProtocol {
    func startTracking()
    func stopTracking()
    func getCurrentSessionTime() -> TimeInterval
    func getAppUsageToday() -> [String: TimeInterval]
    var delegate: UsageTrackingDelegate? { get set }
}
```

#### 2.4 BreakReminderManager.swift
**Responsibility**: Break timer notifications
**Key Components**:
- Break timer management
- Notification scheduling
- Sticky notification handling
- Call-aware timing adjustments

#### 2.5 WellnessManager.swift
**Responsibility**: Health tracking (mate, exercise, mood)
**Key Components**:
- Mate consumption tracking
- Exercise logging
- Mood/energy level monitoring
- Wellness notification triggers

#### 2.6 NotificationManager.swift
**Responsibility**: Centralized notification handling
**Key Components**:
- UNUserNotificationCenter wrapper
- Notification scheduling
- Permission management
- Custom notification types

#### 2.7 PersistenceManager.swift
**Responsibility**: Data storage and retrieval
**Key Components**:
- File I/O operations
- JSON encoding/decoding
- Data migration handling
- Backup/restore functionality

#### 2.8 MenuBarManager.swift  
**Responsibility**: Status item and menu UI
**Key Components**:
- NSStatusItem management
- Menu construction
- UI event handling
- Dynamic menu updates

### Phase 3: Create Coordinators

#### 3.1 WellnessCoordinator.swift
**Responsibility**: Orchestrate wellness-related features
**Dependencies**: WellnessManager, NotificationManager, PersistenceManager
**Coordination Logic**:
- Wellness notification timing
- Motivational phrase scheduling
- Health metric analysis

#### 3.2 ProductivityCoordinator.swift
**Responsibility**: Manage productivity features (usage + breaks)
**Dependencies**: UsageTrackingManager, BreakReminderManager, NotificationManager
**Coordination Logic**:
- Break timing based on usage
- Deep focus session management
- Productivity analytics

### Phase 4: Slim AppDelegate

#### Final AppDelegate Responsibilities:
- App lifecycle management (applicationDidFinishLaunching)
- Single instance check
- Manager initialization and dependency injection
- Coordinator setup
- Hotkey event delegation

**Target size**: ~200 lines (95% reduction)

## Migration Strategy: One Feature Per Commit

**Approach**: Move one feature at a time, test thoroughly, commit, then move to next feature.
**Goal**: Keep each commit focused, testable, and revertible.

### iOS Best Practices Applied:
- **MARK comments** for clear code organization
- **Protocol-oriented design** for testable interfaces  
- **Singleton pattern** for managers (following existing DasungDDC pattern)
- **Delegate pattern** for loose coupling
- **Swift naming conventions** (classes: PascalCase, methods: camelCase)
- **Simple folder structure** (avoid over-engineering)

## Critical Issues from Review (Must Address)

⚠️ **BLOCKING ISSUE**: Python analyzer and Swift app have incompatible JSON schemas:
- **Analyzer expects**: `mateAndSugarRecords` with `timestamp`, `mateAmount`, `sugarLevel`
- **Swift exports**: `mateRecords` with `time`, `thermosCount`, no sugar field
- **Date encoding**: Analyzer expects ISO 8601 strings, Swift exports numeric timestamps

## Implementation Steps (One Commit Each)

### Commit 1: Setup Foundation + Fix Critical Schema Issues
**Goal**: Create structure AND fix analyzer compatibility
**Files**: 
- Create `FastSwitch/Managers/` folder
- Create `FastSwitch/Models/` folder
- Fix JSON encoding in AppDelegate

**Critical Fixes**:
```swift
// Set proper date encoding
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

// Add schema version for future migration
struct ExportedData {
    let schemaVersion = "1.0"
    let dailyData: [String: DailyUsageData]
}
```

**Test**: Project compiles, exported JSON matches analyzer expectations
**Commit**: "refactor: setup foundation and fix analyzer schema compatibility"

### Commit 2: Extract Data Models with Schema Alignment
**Goal**: Move all Codable structs with proper CodingKeys
**Files**:
- Create `Models/DataModels.swift`
- Move all structs from AppDelegate
- Add explicit CodingKeys to match analyzer expectations

**Schema Fixes**:
```swift
struct MateRecord: Codable {
    let time: Date
    let thermosCount: Int
    let type: String
    
    enum CodingKeys: String, CodingKey {
        case time = "timestamp"  // Match analyzer
        case thermosCount = "mateAmount"  // Match analyzer
        case type
    }
}
```

**Test**: App launches, data export/import works with new schema
**Commit**: "refactor: extract data models with analyzer-compatible schema"

### Commit 3: Extract NotificationManager First
**Goal**: Extract notification system (many managers depend on it)
**Files**:
- Create `Managers/NotificationManager.swift`
- Move UNUserNotificationCenter logic
- Add OSLog categories (replace print statements)

**Review Finding**: "Extract NotificationCenter wrapper first because many managers depend on it"

**Test**: All notifications work (break reminders, wellness, etc.)
**Commit**: "refactor: extract notification system to NotificationManager"

### Commit 4: Extract Hotkey System
**Goal**: Move Carbon hotkey handling to separate manager
**Files**:
- Create `Managers/HotkeyManager.swift`
- Move hotkey registration, double-tap detection
- Keep simple delegate pattern

**Test**: All F-key combinations work (F1-F12)
**Commit**: "refactor: extract hotkey system to HotkeyManager"

### Commit 5: Extract App Switching
**Goal**: Move app activation logic to separate manager  
**Files**:
- Create `Managers/AppSwitchingManager.swift`
- Move bundle ID mapping, NSWorkspace activation

**Test**: All app switching works (F1=Chrome, F2=VSCode, etc.)
**Commit**: "refactor: extract app switching to AppSwitchingManager"

### Commit 6: Extract PersistenceManager with Improved Storage
**Goal**: Extract data persistence with better file organization
**Files**:
- Create `Managers/PersistenceManager.swift`
- Move from UserDefaults to daily JSON files
- Path: `~/Library/Application Support/FastSwitch/data/YYYY-MM-DD.json`

**Review Finding**: "UserDefaults for all usage history will grow and is not ideal for larger datasets"

**Test**: Data persistence works, migration from UserDefaults successful
**Commit**: "refactor: extract persistence with daily file storage"

### Commit 7: Extract Usage Tracking
**Goal**: Move session monitoring to separate manager
**Files**:
- Create `Managers/UsageTrackingManager.swift` 
- Move CGEventSource, session timers, app usage tracking

**Test**: Usage tracking works, timers update correctly
**Commit**: "refactor: extract usage tracking to UsageTrackingManager"

### Commit 8: Extract Break Reminders  
**Goal**: Move break notification system
**Files**:
- Create `Managers/BreakReminderManager.swift`
- Move break timers, notification scheduling

**Test**: Break reminders trigger at correct intervals
**Commit**: "refactor: extract break reminders to BreakReminderManager"

### Commit 9: Extract Wellness Features with Opt-in Design
**Goal**: Move mate/exercise/mood tracking with better UX
**Files**:
- Create `Managers/WellnessManager.swift`
- Move wellness data recording, motivational phrases
- Add master toggle (default OFF for new users)

**Review Finding**: "Make wellness opt-in per category, add quiet hours"

**Test**: Wellness tracking works, can be disabled completely
**Commit**: "refactor: extract wellness features with opt-in design"

### Commit 10: Extract Menu Bar UI with i18n Prep
**Goal**: Move status item and menu management
**Files**:
- Create `Managers/MenuBarManager.swift`
- Move NSStatusItem, menu construction
- Centralize strings for future i18n

**Review Finding**: "All strings via a Strings file for i18n"

**Test**: Menu bar shows correctly, all menu items work  
**Commit**: "refactor: extract menu bar UI with i18n preparation"

### Commit 11: Rename Spanish Identifiers to English
**Goal**: Standardize code to English throughout
**Files**:
- Update AppDelegate.swift and all files
- Rename `ochocientosPorSeiscientos` → `eightHundredBySixHundred`
- Keep user-facing strings in Spanish if preferred

**Review Finding**: "Rename Spanish code identifiers to English for consistency"

**Test**: All display modes work with new identifiers
**Commit**: "refactor: standardize code identifiers to English"

### Commit 12: Slim AppDelegate to Coordination Only
**Goal**: Remove all business logic from AppDelegate
**Files**:
- Update `AppDelegate.swift`
- Keep only: app lifecycle, manager initialization, event routing
- Add single instance check

**Test**: Full app functionality works exactly as before
**Commit**: "refactor: slim AppDelegate to coordination only"

### Final Result:
- **AppDelegate**: ~150 lines (96% reduction from 4270)  
- **12 focused files**: Each with single responsibility
- **Full test coverage**: Every commit tested before merge
- **Zero behavior change**: App works identically to before
- **Critical issues resolved**: Analyzer schema compatibility, improved storage

## Additional Critical Fixes (Based on Review)

### Quick Wins to Address After Refactor:
1. **Bundle ID Consistency**: Choose `com.bandonea.FastSwitch` everywhere (README, scripts, code)
2. **Fill `scripts/clean.sh`**: Move reset steps from README to this script
3. **OSLog Implementation**: Replace all `print` statements with categorized logging
4. **Schema Version**: Add versioning for future data migration safety
5. **UserDefaults Cleanup**: Keep only settings, move data to files

### Schema Alignment Details:
The review identified critical incompatibility between the Python analyzer and Swift app:

**Current Swift Schema Issues**:
- Uses numeric Date encoding instead of ISO 8601
- Field names don't match: `time` vs `timestamp`, `thermosCount` vs `mateAmount`  
- Missing `sugarLevel` field that analyzer expects
- `dailyReflection` location differs

**Fix Strategy**:
1. Set `JSONEncoder.dateEncodingStrategy = .iso8601`
2. Add `CodingKeys` to map Swift properties to analyzer-expected JSON keys
3. Add missing fields or make them optional in analyzer
4. Add `schemaVersion` field for future migration support

## Success Metrics

### Quantitative Goals:
- **AppDelegate size**: From 4270 → ~200 lines (95% reduction)
- **File count**: 13 new focused files
- **Test coverage**: 80%+ for each manager
- **Build time**: No degradation
- **Memory usage**: No increase

### Qualitative Goals:
- **Maintainability**: Each file has single responsibility
- **Testability**: Components can be tested in isolation
- **Readability**: Clear separation of concerns
- **Extensibility**: Easy to add features without touching AppDelegate
- **Debugging**: Issues can be traced to specific managers

## Risk Mitigation

### High-Risk Areas:
1. **Carbon Hotkey System** - Complex low-level code
2. **Data Migration** - Ensure existing user data works
3. **Notification Timing** - Break timers must remain accurate
4. **App Activation** - Bundle ID mappings must preserve behavior

### Mitigation Strategies:
- **Incremental approach** - Extract one system at a time
- **Comprehensive testing** - Test each extraction thoroughly
- **Backup strategy** - Keep original AppDelegate until confident
- **User testing** - Verify all features work as before
- **Rollback plan** - Easy to revert if issues found

## Implementation Timeline

**Total Estimated Time**: 2-3 days

- **Day 1**: Steps 1-6 (Foundation, Models, Core Systems)
- **Day 2**: Steps 7-10 (Tracking, Reminders, UI)  
- **Day 3**: Steps 11-13 (Coordinators, Final Refactor, Testing)

## Post-Refactor Benefits

### Developer Experience:
- **Faster debugging** - Issues isolated to specific files
- **Easier testing** - Components can be mocked and tested independently
- **Better code review** - Changes confined to relevant managers
- **Simpler onboarding** - New developers can understand focused files

### Code Quality:
- **Reduced coupling** - Clean interfaces between components
- **Increased cohesion** - Related functionality grouped together
- **Better error handling** - Errors contained within domains
- **Improved performance** - More efficient memory usage

### Future Development:
- **Feature addition** - New features don't touch AppDelegate
- **Platform expansion** - Managers could be reused for iOS version
- **Third-party integration** - Clean APIs for external integrations
- **Architecture evolution** - Foundation for SwiftUI migration

---

*This refactoring plan maintains 100% behavioral compatibility while dramatically improving code organization, testability, and maintainability.*