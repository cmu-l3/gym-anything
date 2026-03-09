# Android Studio Environment - Evidence Documentation

## Environment Summary
- **Environment**: android_studio_env@0.1
- **Application**: Android Studio Ladybug 2024.2.1 Patch 2
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 8GB RAM, networking enabled
- **Tasks**: 5 (create_new_project, import_gradle_project, fix_build_errors, add_unit_test, refactor_rename_class)

## Checklist

- [x] Installation script completes without errors
- [x] Setup script completes without errors
- [x] Application is visible in screenshot (see screenshots below)
- [x] Application is in correct initial state (Welcome screen)
- [x] Task setup runs without errors for all 5 tasks
- [x] Export script produces valid JSON
- [x] Verifier can read and process the result
- [x] Verification returns expected result for all 5 tasks
- [x] Interactive test: agent can open project via GUI and score 100/100

## Test Results

### Environment Boot & Installation
- **Status**: PASS
- **Installation time (pre_start)**: ~669 seconds
- **Setup time (post_start)**: ~145 seconds (from checkpoint)
- **Task-specific setup time**: ~80-137 seconds (varies by task)
- **Total boot time**: ~785 seconds (first run), ~283 seconds (from checkpoint)

### Pre-start Log (key outputs)
```
=== Installing Android Studio ===
Installing OpenJDK 17...
Downloading Android Studio...
Extracting Android Studio...
Android Studio installed at /opt/android-studio
Setting up Android SDK...
Accepting SDK licenses...
Installing SDK components...

Installed packages:
  build-tools;34.0.0   | 34.0.0  | Android SDK Build-Tools 34
  cmdline-tools;latest | 20.0    | Android SDK Command-line Tools
  platform-tools       | 36.0.2  | Android SDK Platform-Tools
  platforms;android-34 | 3       | Android SDK Platform 34

=== Android Studio installation complete ===
```

### Post-start Log
```
=== Setting up Android Studio ===
Android Studio build: AI-242.23339.11.2421.12550806
Using config directory name: AndroidStudio2024.2
Launching Android Studio...
Waiting for Android Studio to start...
```

### Env Setup Timing (from actual log)
```
Profiling time for env setup: 669.2799098491669s
Profiling time for task specific hooks: 81.17904257774353s
Env setup took 750.4593358039856 seconds
```

## Interactive Testing Evidence

### 1. Android Studio Welcome Screen
- **Screenshot**: `01_welcome_screen_with_open_dialog.png`
- Android Studio launches to Welcome screen with "Open File or Project" dialog visible
- Shows Projects, Customize, Plugins, Learn tabs on left
- Dialog shows file browser navigated to `/home/ga` with AndroidStudioProjects folder visible

### 2. Project Loading
- **Screenshot**: `02_project_loading_spinner.png`
- After selecting SunflowerApp path and pressing Enter, loading spinner appears
- Android Studio is importing the Gradle project

### 3. Project Loaded Successfully
- **Screenshot**: `03_project_loaded_sunflowerapp.png`
- SunflowerApp project fully loaded in Android Studio
- Window title: "SunflowerApp - settings.gradle.kts (:)"
- Project tree visible with app module, Gradle scripts, etc.
- Editor shows settings.gradle.kts content
- "What's New in Ladybug" assistant panel visible

### 4. Verifier Result After Interactive Test (import_gradle_project)
```json
{
  "passed": true,
  "score": 100,
  "feedback": "Project opened in IDE (.idea/ exists): PASS [35/35] | Gradle sync completed (.gradle/ exists): PASS [30/30] | settings.gradle.kts correct (name + :app): PASS [15/15] | build.gradle.kts valid (Android + Kotlin plugins): PASS [8/8] | Plant.kt valid (5/5 checks): PASS [6/6] | PlantRepository.kt valid (5/5 checks): PASS [6/6] | Perfect score - project fully imported and synced!"
}
```

## Baseline Scores (All 5 Tasks)

All baselines tested through the framework with `env.step([], mark_done=True)` - no agent action.

| Task | Baseline Score | Passed | Details |
|------|---------------|--------|---------|
| create_new_project | 0 | False | Project directory not found at expected location (0/10) |
| import_gradle_project | 35 | False | Source files exist (settings 15 + build.gradle 8 + Plant.kt 6 + PlantRepository.kt 6 = 35pts) but .idea/ (0/35) and .gradle/ (0/30) missing. Pass threshold: 80 |
| fix_build_errors | 0 | False | All 4 bugs still present, build fails. Missing import (0/15), type mismatch (0/15), syntax error (0/15), missing dependency (0/15), build failed (0/40) |
| add_unit_test | 0 | False | No test files found. NoteValidatorTest.kt not found, NoteFormatterTest.kt not found, NoteTest.kt not found |
| refactor_rename_class | 0 | False | CalcEngine.kt still exists (+0), Calculator.kt not found (+0), no methods renamed |

### Score Interpretation
- **create_new_project (0)**: WeatherTracker directory doesn't exist - agent must create new project via Android Studio New Project wizard
- **import_gradle_project (35)**: SunflowerApp source files pre-exist (copied by setup_task.sh) contributing 35pts, but .idea/ (35pts) and .gradle/ (30pts) require opening in IDE. Agent action raises score from 35 to 100. Pass threshold is 80
- **fix_build_errors (0)**: BrokenApp has 4 intentional errors that must be manually fixed. No hint comments in source files
- **add_unit_test (0)**: NotepadApp has no test files - agent must write 3 test classes
- **refactor_rename_class (0)**: CalcEngine.kt must be renamed to Calculator.kt with 5 method renames. No solution hints in source files

## Verified Score After Agent Action (import_gradle_project)
- **Score**: 100/100
- **Method**: Used ask_cua.py to locate "Open" button, clicked it, navigated to SunflowerApp, pressed Enter
- **Result**: .idea/ and .gradle/ directories created, all 6 criteria pass

## Window Detection Evidence
```
$ DISPLAY=:1 wmctrl -l
0x02000003 -1 ga-base @!0,0;BDHF
0x006000e7  0 ga-base SunflowerApp – settings.gradle.kts (:)
```

## Export Result JSON (import_gradle_project)
```json
{
  "idea_dir_exists": true,
  "gradle_cache_exists": true,
  "build_dir_exists": false,
  "plant_kt_exists": true,
  "plant_repo_exists": true,
  "android_studio_running": false,
  "window_title": ""
}
```

## Data Sources
- **SunflowerApp**: Based on Google's Android Sunflower sample (garden plant tracker)
  - Real Kotlin data classes with proper documentation
  - Uses AndroidX/Material Design dependencies
  - Gradle Kotlin DSL build system (AGP 8.2.0, Kotlin 1.9.22, compileSdk 34)
- **BrokenApp**: SunflowerApp variant with 4 intentional build errors
- **NotepadApp**: Simple notepad app with Note, NoteValidator, NoteFormatter classes
- **CalculatorApp**: Calculator with poorly-named CalcEngine class for refactoring

## SDK Components Installed
- platform-tools 36.0.2
- platforms;android-34 (API 34)
- build-tools;34.0.0
- cmdline-tools;latest (20.0)

## Audit Fixes Applied

### Audit Round 1
1. **CRITICAL - Removed hint comments from BrokenApp**: `// BUG:` comments in all 4 source files removed so agents can't just follow the hints
2. **CRITICAL - Removed solution comment from CalcEngine.kt**: `NOTE:` comment listing exact rename mappings removed
3. **CRITICAL - Reweighted import_gradle_project verifier**: IDE-dependent criteria now dominate; static file criteria reduced. Pass threshold raised to 80
4. **MEDIUM - Fixed hash comparison bug**: `setup_task.sh` and `export_result.sh` used same variable names for file paths and hashes. Fixed with distinct `ORIG_*_HASH` variable names
5. **LOW - Rewrote fix_build_errors verifier**: Now uses `copy_from_env` directly to read source files instead of relying on export JSON
6. **LOW - Fixed task descriptions**: Tasks 3-5 now correctly state "project is already open"

### Audit Round 2
7. **CRITICAL - Fixed task start state reliability**: `setup_android_studio_project()` in task_utils.sh now kills existing Android Studio before launching, includes retry logic (up to 3 attempts), and verifies the project window actually appeared. This fixes the "Cannot Execute Command" error seen in screenshots
8. **CRITICAL - Added missing Gradle wrapper JAR**: `gradle-wrapper.jar` (63KB, Gradle 8.4) added to all 4 data projects (BrokenApp, SunflowerApp, NotepadApp, CalculatorApp). Without this, `./gradlew` failed with `ClassNotFoundException: GradleWrapperMain`
9. **CRITICAL - Further reweighted import_gradle_project verifier**: .idea/=35pts, .gradle/=30pts, build.gradle=8pts, Plant.kt=6pts, PlantRepository.kt=6pts, settings=15pts. Baseline now 35/100 (was 45), pass threshold 80
10. **MEDIUM - Simplified fix_build_errors description**: Removed error category hints ("Missing imports", "Type mismatches", etc.). Description now just says "fix all build errors". Removed `error_files` metadata listing specific files
11. **MEDIUM - Rewrote add_unit_test verifier**: Now uses `copy_from_env` to read test files directly, with export JSON as fallback only
12. **MEDIUM - Rewrote refactor_rename_class verifier**: Now uses `copy_from_env` to read Calculator.kt, CalcEngine.kt, CalcActivity.kt directly
13. **LOW - Removed unnecessary "Open Plant.kt" step**: import_gradle_project description no longer asks agent to open Plant.kt in editor (verifier doesn't check this)
14. **CRITICAL - Fixed echo→printf JSON escape bug**: All export scripts used `echo "$VAR" | python3 -c "json.dumps(sys.stdin.read())"` which produced `"\n"` for empty variables (echo adds trailing newline). Changed to `printf '%s'` to avoid spurious content. Also added `.strip()` to verifier fallback reads. This fixed false-positive baselines: add_unit_test was 12 (now 0), refactor_rename_class was 10 (now 0)
15. **CRITICAL - Re-ran all 5 baseline tests**: Confirmed all baselines match expectations: create_new_project=0, import_gradle_project=35, fix_build_errors=0, add_unit_test=0, refactor_rename_class=0. Total test time: 19.5 min (using pre_start cache)

## Key Technical Learnings
1. **needrestart suppression**: Must add `NEEDRESTART_MODE=l` and create `/etc/needrestart/conf.d/99-noninteractive.conf` to prevent SSH restarts during apt-get install
2. **QEMU lifecycle**: Background bash processes send SIGTERM to child QEMU processes on exit; use nohup+disown to keep QEMU alive
3. **First-run dialog suppression**: Requires idea.properties, VM options, Java preferences, trusted-paths.xml, and consent files
4. **Gradle sync timing**: .gradle/ directory created within seconds of opening project, but specific probe files may take longer
5. **Pre-start checkpoint**: Saves ~530s on subsequent runs by caching the install phase
6. **Verifier design**: IDE-interaction-dependent criteria should be weighted higher than static file content to prevent high baselines
7. **No hint comments**: Source files with intentional bugs should not contain comments pointing to the solution
8. **Gradle wrapper JAR**: Android projects need `gradle/wrapper/gradle-wrapper.jar` in addition to `gradle-wrapper.properties`. Without it, `./gradlew` fails with `ClassNotFoundException`. Extract from official Gradle distribution
9. **Task start state**: Always kill existing IDE instances before opening a new project to avoid IPC race conditions. Verify the project window appeared with retry logic
10. **echo vs printf for JSON**: `echo "$VAR"` appends a newline, so `echo "" | python3 json.dumps(stdin)` produces `"\n"` not `""`. Use `printf '%s' "$VAR"` in export scripts. Also `.strip()` fallback values in verifiers
