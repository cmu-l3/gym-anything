> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Android Environment Patterns

## Overview

When the target environment is an Android AVD (Android Virtual Device), verification works fundamentally differently from Linux or Windows desktop environments. There is no filesystem database to query and no structured config file to parse — the application's entire visible state lives in the UI. This document covers the key adaptations required for task scripts, verification, and testing.

---

## 1. The Primary Verification Mechanism: `uiautomator dump`

**All Android task verification is based on UI XML dumps, not database queries or file reads.**

```bash
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null
```

This dumps the full UI accessibility tree of the currently visible screen to an XML file. The verifier then reads this XML via `copy_from_env`.

**Key workflow for export_result.sh:**
1. Navigate the app to the screen containing the data you want to verify
2. Wait for the screen to fully render (sleep 1-3s)
3. Dump the XML: `uiautomator dump /sdcard/ui_dump_<task>.xml 2>/dev/null`
4. Grep the XML for the expected values
5. Write a result JSON to `/sdcard/<task_name>_result.json`

**Key workflow for verifier.py:**
```python
copy_from_env('/sdcard/<task_name>_result.json', tmp.name)
with open(tmp.name, 'r', encoding='utf-8-sig') as f:
    result = json.load(f)
```

---

## 2. Two XML Attributes: `text` vs `content-desc`

Android UI elements store their visible text in two different attributes — and which one is used depends on the widget type and how the developer chose to expose accessibility information.

| Widget type | Typical attribute used |
|-------------|----------------------|
| `EditText`, `TextView` (simple) | `text` |
| Compound list items, section headers with sub-labels | `content-desc` |
| Spinners / dropdowns after selection | `content-desc` |
| Settings panels with multi-line headers | `content-desc` |

**Critical**: A section header that says "Home Airport\nSelect Airport\nORD" will appear in `content-desc` — **not** in `text`. Similarly, a dropdown that shows "Captain" as the selected value may encode that in `content-desc` with the section label.

**Pattern for multi-line content-desc** (Android encodes `\n` as `&#10;` in XML):
```
content-desc="Home Airport&#10;Select Airport&#10;ORD"
```

**How to grep for it:**
```bash
# Will match regardless of how the value is embedded in content-desc
grep -q "ORD" /sdcard/airports.xml && HOME_FOUND=true || HOME_FOUND=false
```

**Discovery approach**: When unsure which attribute a value appears in, dump the XML and inspect it manually:
```bash
uiautomator dump /sdcard/debug.xml
cat /sdcard/debug.xml | grep -o '.\{0,40\}TARGET_VALUE.\{0,40\}'
```

---

## 3. Inline-Expanding Sections Require Sleep After Tap

Many Android settings screens use "expand in place" patterns — tapping a section header expands it to reveal sub-options without navigating to a new screen. **The expanded content does NOT appear in the XML dump immediately.** You must sleep 3-5 seconds after tapping before dumping.

```bash
# WRONG: dump immediately after tap
am shell input tap $X $Y
uiautomator dump /sdcard/section.xml   # expanded content missing!

# CORRECT: wait for animation and render
am shell input tap $X $Y
sleep 4
uiautomator dump /sdcard/section.xml   # expanded content now present
```

**Why 4 seconds?** Android's expand animation takes ~300ms, but the accessibility tree may not update until after the animation and any data-loading completes. For settings screens that load data (e.g., airport lists from a network or local DB), the content may take 2-4 seconds to populate.

**How to find the tap coordinates**: First dump the XML in the unexpanded state, find the element's `bounds` attribute (e.g., `bounds="[0,1234][1080,1356]"`), compute center: `X = (0+1080)/2 = 540`, `Y = (1234+1356)/2 = 1295`.

---

## 4. Multi-Section Export Requires Multiple Navigations

When verification requires checking multiple separate areas of an app (e.g., Friends list + Settings > General + Settings > Airports + Settings > Personalization), each area requires its own navigation sequence and XML dump. **There is no single dump that captures everything.**

**Pattern for export_result.sh:**
```bash
# Navigate to section 1 (e.g., Friends)
input tap $HAMBURGER_X $HAMBURGER_Y; sleep 1
input tap $FRIENDS_MENU_X $FRIENDS_MENU_Y; sleep 2
uiautomator dump /sdcard/friends.xml 2>/dev/null

# Navigate to section 2 (e.g., Settings)
input tap $HAMBURGER_X $HAMBURGER_Y; sleep 1
input tap $SETTINGS_MENU_X $SETTINGS_MENU_Y; sleep 2
uiautomator dump /sdcard/settings.xml 2>/dev/null

# Navigate to section 3 (e.g., an inline-expanding sub-section)
# (may need to scroll first)
input swipe 540 1200 540 400 500; sleep 1   # scroll down
uiautomator dump /sdcard/scrolled.xml 2>/dev/null
# Find expand button coordinates from scrolled.xml, then tap:
input tap $EXPAND_X $EXPAND_Y; sleep 4
uiautomator dump /sdcard/expanded.xml 2>/dev/null
```

**Coordinate discovery**: Parse `bounds` from the XML to get coordinates dynamically. Hardcoded coordinates are a fallback, but bounds-based coordinates are more robust across different screen states.

---

## 5. `pm clear` as the Baseline Reset Mechanism

For Android app tasks, `pm clear <package_name>` is the standard way to guarantee a clean, uniform starting state. It wipes all app data (shared preferences, internal DB, cached state) back to factory defaults.

```bash
pm clear com.example.app
sleep 2
```

**Key properties of `pm clear`:**
- Wipes ALL local app state (user settings, login credentials, cached data)
- The app will require fresh login after `pm clear`
- All user-configured preferences (airports, time format, etc.) are lost
- There are NO default values for most settings (they show as unset/blank)

**Anti-gaming benefit**: Because `pm clear` wipes everything, the do-nothing test is guaranteed to return all-False for any setting the agent was supposed to configure. There is no need to separately record a "baseline" — the post-clear state is always the baseline.

**After `pm clear`, always re-login:**
```bash
pm clear com.example.app
sleep 2
# Use environment's login helper
bash /workspace/scripts/login_helper.sh
```

---

## 6. Shell Scripts Must Use POSIX sh, Not Bash

Android's shell (`/system/bin/sh`) is a POSIX-compatible shell, **not** bash. Do not use bash-specific features.

```bash
# WRONG: bash-specific
#!/bin/bash
[[ "$VAR" == "value" ]]   # double brackets
echo $((expr))            # arithmetic may work but prefer let
for i in {1..5}; do ...   # brace expansion NOT supported

# CORRECT: POSIX sh
#!/system/bin/sh
[ "$VAR" = "value" ]      # single bracket, single =
i=1; while [ $i -le 5 ]; do ...; i=$((i+1)); done
```

**Shebang must be:**
```bash
#!/system/bin/sh
```

**Common gotchas:**
- No `[[ ]]` — use `[ ]`
- No `==` in `[ ]` — use `=`
- No `source` — use `.` (dot)
- No `echo -e` — use `printf` for escape sequences
- No process substitution (`<(...)`)

---

## 7. Keyword False Positives from Full-Screen Navigation Menu Items

**Problem**: An Android app's main menu or navigation drawer may contain item labels that look like verification keywords. If you grep for those keywords in a full-screen XML dump (not narrowed to a specific section), the grep will find the navigation menu items and report a false positive.

**Example**: An app with navigation items labeled "Three Phase Calculator", "Single Phase Power" — grepping for "Three Phase" in a full dump will find the menu item even before the agent has done any calculation.

**The Fix**: Use one of these approaches:

1. **Navigate away from the menu first**, then dump. If the verification screen is distinct from the navigation menu, the menu items won't appear in the dump.

2. **Gate keyword criteria on also having a numeric result nearby**:
```bash
# BAD: keyword alone
grep -q "Three Phase" /sdcard/dump.xml && FOUND=true

# GOOD: keyword AND a computed numeric value
if grep -q "Three Phase" /sdcard/dump.xml && grep -qE "[0-9]{4,}" /sdcard/dump.xml; then
    FOUND=true
fi
```

3. **Parse the XML structurally** — find the parent element of the keyword and verify it has the right element type (e.g., a result display, not a navigation button).

**Discovery**: After writing your export script, run it on a freshly-cleared VM (do-nothing state) and inspect which grepped keywords are triggering. Any that return `true` in do-nothing must be fixed.

---

## 8. Result JSON Path Convention for Android

Store the result JSON in `/sdcard/` (the Android shared storage, accessible from the VM):

```bash
/sdcard/<task_name>_result.json
```

In `verifier.py`, copy from the same path:
```python
copy_from_env('/sdcard/<task_name>_result.json', tmp.name)
```

Do NOT use `/tmp/` on Android — it may be volatile and cleaned up differently than on Linux.

---

## 9. Script Structure Template

**`setup_task.sh`** (runs before the agent starts):
```bash
#!/system/bin/sh
echo "=== Setting up <Task Name> ==="

# 1. Reset app state
pm clear com.example.app
sleep 2

# 2. Log in
. /workspace/scripts/login_helper.sh

echo "=== Setup Complete ==="
```

**`export_result.sh`** (runs after the agent finishes):
```bash
#!/system/bin/sh
echo "=== Exporting <Task Name> Result ==="

TASK="<task_name>"

# 1. Navigate to screen 1 and dump XML
input tap $HAMBURGER_X $HAMBURGER_Y; sleep 1
input tap $SECTION1_X $SECTION1_Y; sleep 2
uiautomator dump /sdcard/${TASK}_section1.xml 2>/dev/null

# 2. Grep for expected values
CRIT1_FOUND=false
grep -q "ExpectedValue1" /sdcard/${TASK}_section1.xml && CRIT1_FOUND=true

# 3. Navigate to screen 2 with inline expansion
input tap $HAMBURGER_X $HAMBURGER_Y; sleep 1
input tap $SETTINGS_X $SETTINGS_Y; sleep 2
input swipe 540 1200 540 400 500; sleep 1   # scroll to section
input tap $EXPAND_X $EXPAND_Y; sleep 4      # expand and wait
uiautomator dump /sdcard/${TASK}_section2.xml 2>/dev/null

CRIT2_FOUND=false
grep -q "ExpectedValue2" /sdcard/${TASK}_section2.xml && CRIT2_FOUND=true

# 4. Write result JSON
cat > /sdcard/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "criterion1_found": $CRIT1_FOUND,
    "criterion2_found": $CRIT2_FOUND
}
EOF

echo "=== Export Complete ==="
```

**`verifier.py`** (same pattern as other environments):
```python
import json, tempfile, os

def verify_<task_name>(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "<task_name>"
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env(f'/sdcard/{task_name}_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — agent may not have completed export"}

    score = 0
    parts = []

    if result.get('criterion1_found'):
        score += 50
        parts.append("Criterion 1 met (50/50)")

    if result.get('criterion2_found'):
        score += 50
        parts.append("Criterion 2 met (50/50)")

    return {
        "passed": score >= 60,
        "score": min(score, 100),
        "feedback": " | ".join(parts) or "No criteria met"
    }
```

---

## 10. Common Android-Specific Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Script uses `#!/bin/bash` | Script fails with "bad interpreter" on device | Use `#!/system/bin/sh` |
| Dump immediately after tap | Expanded content missing from XML | Add `sleep 4` after tapping expand sections |
| Grepping `text=` when value is in `content-desc` | Always False (missed values) | Check which attribute the app uses; inspect raw XML |
| Grepping full-screen XML for navigation keywords | False positive in do-nothing | Navigate away from menu first, or gate on numeric result |
| Result JSON at `/tmp/` | File not found (volatile) | Use `/sdcard/<task_name>_result.json` |
| Using `==` in `[ ]` | Syntax error on device shell | Use `=` (single equals) in POSIX `[ ]` |
| Missing `sleep` after `pm clear` | App not ready for login | `sleep 2` minimum after `pm clear` |
| Coordinates based on 1280×720 assumed resolution | Wrong tap location | Check actual device resolution via `wm size`; device may be 1080×2400 or similar |

---

## 11. Stateless Reference Apps: Use Force-Stop + Relaunch Instead of pm clear

Section 5 above describes `pm clear` for apps that accumulate **user-generated state** (login sessions, saved records, user-uploaded content). However, read-only reference apps — medical databases, calculators, documentation viewers, reference guides — typically carry **no user-generated state**. For these apps, `pm clear` is unnecessary and can have unintended side effects (wiping cached data files or resetting configuration needed for the app to function correctly).

### When to Use Each Reset Strategy

| App Type | State to Clear | Reset Strategy |
|----------|----------------|----------------|
| Apps with login / user accounts | Session tokens, cookies, stored user data | `pm clear <package>` then `sleep 2` |
| Apps with locally created records | Database rows, files created by user actions | `pm clear <package>` then `sleep 2` |
| Read-only reference apps (no user state) | Navigation stack / UI state only | `am force-stop <package>` then relaunch via `monkey` |
| Apps that require pre-loaded config | Pre-loaded database or config files | `am force-stop` only — `pm clear` would wipe needed assets |

### How to Distinguish

Ask yourself: **"Can a fresh install of this app complete the task without any user setup?"**
- If **yes** (app works immediately upon launch): use `force-stop + monkey` — no user state needs clearing.
- If **no** (user must log in, create an account, or enter initial data): use `pm clear` to ensure a clean baseline.

### setup_task.sh Template for Stateless Reference Apps

```sh
#!/system/bin/sh
# Reset to Welcome screen — no pm clear needed (no user-generated state)
am force-stop com.example.referenceapp
sleep 1
monkey -p com.example.referenceapp -c android.intent.category.LAUNCHER 1
sleep 3
```

### Why This Matters for Verification

The do-nothing baseline for a stateless reference app should show all result flags as `false` simply because the agent never navigated anywhere — not because user data was wiped. If a `pm clear` step accidentally removes pre-loaded reference data that the app needs, setup will fail in unpredictable ways. Use the minimal reset that achieves a known starting screen.

---

## 12. Prefer Direct Data Reads Over UI Scraping When Possible

Sections 1–4 describe `uiautomator dump` as the primary Android verification mechanism — and it is the right default. However, many production Android apps persist their state to **structured data stores** accessible without navigating the UI:

| Storage type | Location pattern | Requires root? |
|---|---|---|
| SQLite databases | `/data/data/<package>/databases/<db_name>` | Yes |
| SharedPreferences XML | `/data/data/<package>/shared_prefs/<prefs_name>.xml` | Yes |
| Plain config files | `/data/data/<package>/files/` | Usually yes |
| SD card / public files | `/sdcard/<path>` | No |

**When direct data access is available, prefer it over UI scraping.** The reasons:

- **Reliability**: Doesn't depend on app navigation state, UI animations, or screen rendering
- **Completeness**: Reads ALL values regardless of whether they're currently visible on screen
- **No false positives**: Reading a preference value of `"1"` is unambiguous; grepping XML for a label can match navigation items
- **No timing issues**: No need for `sleep` after taps or waiting for animations

**How to discover what structured data an app uses:**
```sh
# List all databases
su 0 ls /data/data/<package>/databases/

# List all SharedPreferences files
su 0 ls /data/data/<package>/shared_prefs/

# Dump a SharedPreferences file to see all keys
su 0 cat /data/data/<package>/shared_prefs/<prefs>.xml

# Query a SQLite database
su 0 sqlite3 /data/data/<package>/databases/<db> ".tables"
su 0 sqlite3 /data/data/<package>/databases/<db> "SELECT * FROM <table> LIMIT 5;"
```

**When to still use `uiautomator dump`:**
- Verification requires confirming what is currently *visible* to the user (e.g., a value displayed on the map screen)
- The app encrypts or obfuscates its on-disk storage
- The data of interest is not persisted to disk until a specific user action (e.g., "Save" button)

---

## 13. Always Verify Preference/Config Key Names Against a Live Device

**Never assume a config or preference key name from documentation, source code inspection, or other tasks in the same app.** Key names frequently differ from what is described in documentation or implied by the UI label.

**The canonical workflow:**
```sh
# 1. Run the app and change the setting you care about via the UI
#    (just once, so the key appears in the prefs file)

# 2. Dump the prefs file and search for the expected value
su 0 cat /data/data/<package>/shared_prefs/*.xml | grep -i "<keyword>"

# 3. Confirm the exact key name as it appears in the file
# Example: you expected "preferenceKey_laneGuidance" but the file shows
#          "preferenceKey_navigation_laneGuidance"
```

**Real example**: A navigation app had a "Lane guidance" toggle. The assumed key name `preferenceKey_laneGuidance` did not exist in the preferences file. The actual key was `preferenceKey_navigation_laneGuidance`. A setup script using the wrong key silently had no effect.

**This is mandatory for every new key you use in a setup or export script.** One wrong key name causes the entire criterion to fail silently — the setup sets nothing, the export reads nothing, and the verifier scores 0 for that criterion even when the agent correctly changes the setting.

---

## 14. Verify That Setup Changes Persist Through App Launch

When `setup_task.sh` modifies a config file (SharedPreferences XML, SQLite DB) before launching the app, the app may **read the modified file on startup but then overwrite it** with its own in-memory state when force-stopped — depending on how the app manages its preference lifecycle.

**Always test empirically:**
```sh
# Step 1: Force-stop the app
am force-stop <package>

# Step 2: Apply your config changes (sed, sqlite3, etc.)
sed -i 's/name="someKey" value="[^"]*"/name="someKey" value="newValue"/' <prefs_file>

# Step 3: Launch the app
monkey -p <package> -c android.intent.category.LAUNCHER 1
sleep 12  # wait for full initialization

# Step 4: Read the config file AGAIN to check if changes survived
grep 'someKey' <prefs_file>
# If it still shows "newValue" → changes persist ✓
# If it shows the old value → app overwrote your changes ✗
```

**If the app overwrites your changes:**
- Try applying changes AFTER the app has launched and is idle (use `sleep` + apply while running), then force-stop to flush
- Use the app's own settings API if available (intent-based settings, etc.)
- Reconsider whether the setting is stored where you think it is — check all prefs files and databases

**If changes persist (the common case):** proceed with confidence that the `setup_task.sh` approach is sound. The force-stop in `export_result.sh` will flush the agent's changes back to disk, and you can then read the final values reliably.

---

## 15. Settings-Only Tasks: Record Baseline at Setup Time, Not Hardcoded Defaults

For tasks that require changing **settings** (with no structural artifact like a new database record), the gate check must compare final values against the baseline values at setup time — not against hardcoded "expected default" values.

**Why hardcoded defaults are wrong:**
- A previous task's setup script may have left the app in a non-default state
- The same environment may be used across multiple task episodes in sequence
- The app itself may have updated default values across versions

**Correct pattern:**
```sh
# In setup_task.sh: record actual current values as baseline
BASELINE_THEME=$(grep 'preferenceKey_app_theme' "$PREFS" | sed 's/.*>\([^<]*\)<.*/\1/')
echo "$BASELINE_THEME" > /data/local/tmp/<task>_baseline_theme

# Then set the "wrong" starting state:
sed -i 's|name="preferenceKey_app_theme">[^<]*|name="preferenceKey_app_theme">0|' "$PREFS"
```

```sh
# In export_result.sh: read and re-export the baseline alongside the current value
BASELINE_THEME=$(cat /data/local/tmp/<task>_baseline_theme 2>/dev/null || echo "0")
CURRENT_THEME=$(grep 'preferenceKey_app_theme' "$PREFS" | sed 's/.*>\([^<]*\)<.*/\1/')
```

```python
# In verifier.py: gate check compares current vs baseline (not hardcoded)
b_theme = str(result.get('baseline_theme', '0'))
theme = str(result.get('app_theme', ''))
any_changed = theme != b_theme  # or check all settings
if not any_changed:
    return {"passed": False, "score": 0, "feedback": "No settings changed from starting state"}
```

**Why this works even when the app is already in the "correct" state at setup:** If the current value already matches the target, the setup's "wrong state" sed command changes it away from the target, the agent changes it back, and the gate passes. If somehow the sed command doesn't work for a particular pref, the baseline comparison still correctly captures that the value didn't change — score 0 for that criterion.

---

## 16. SQLite-Based Mobile App Verification: WAL Checkpoint and Protected Directory Copy

Many mobile GIS, field data collection, and database apps (e.g., QField, Survey123, QGIS Mobile) store their working data in SQLite databases — often as GeoPackage `.gpkg` files. Verifying the agent's edits requires correctly flushing and accessing these files. Two closely related issues must be handled together.

### Issue A: SQLite WAL (Write-Ahead Logging)

SQLite in WAL mode stores uncommitted writes in a sidecar file (e.g., `mydata.gpkg-wal`). The **main `.gpkg` file does NOT reflect the agent's changes** until the WAL is checkpointed. WAL checkpoint happens automatically when the last database connection closes — which occurs when the app process is killed.

### Issue B: App-Private Directory Access

Android apps store their files in protected directories (e.g., `/sdcard/Android/data/<package>/files/`) that may require elevated permissions for ADB to read. `copy_from_env` (which uses ADB pull) can fail silently or return a partial/empty file from these paths.

### The Combined Solution: `post_task.sh`

```sh
#!/system/bin/sh
PACKAGE="ch.opengis.qfield"
GPKG_APP="/sdcard/Android/data/ch.opengis.qfield/files/<task>.gpkg"
GPKG_OUT="/sdcard/<task>_result.gpkg"

# Step 1: Force-stop the app → triggers SQLite WAL checkpoint
am force-stop $PACKAGE
sleep 3   # allow WAL merge to complete

# Step 2: Copy to /sdcard/ (universally readable via ADB / copy_from_env)
cp "$GPKG_APP" "$GPKG_OUT"
chmod 644 "$GPKG_OUT"
```

**In `verifier.py`** — read from the copied path, not the app's live database:

```python
import sqlite3, tempfile, os

def check_<task>(traj, env_info, task_info):
    result_path = task_info.get('metadata', {}).get('result_file',
        '/sdcard/<task>_result.gpkg')
    tmp = tempfile.mktemp(suffix='.gpkg')
    try:
        env_info['copy_from_env'](result_path, tmp)
        conn = sqlite3.connect(tmp)
        # Agent's edits are now fully reflected in this file
        rows = conn.execute("SELECT * FROM <table>").fetchall()
        conn.close()
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
```

### Identifying Apps That Use SQLite

- GeoPackage (`.gpkg`), MBTiles (`.mbtiles`), SQLite (`.sqlite`, `.db`) files are all SQLite databases
- `file /sdcard/Android/data/<package>/files/*.gpkg` confirms: `SQLite 3.x database`
- Any app that modifies data on-device without an explicit "Export" feature likely uses SQLite internally

### Critical Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| `copy_from_env` called before `am force-stop` | WAL not checkpointed; main file shows pre-edit state | Always force-stop before copying |
| Reading from app-private directory directly | ADB permission error or empty/corrupt file | Copy to `/sdcard/` first in `post_task.sh` |
| `sleep` too short after `force-stop` | WAL write still in progress | Use `sleep 3` minimum; increase to `sleep 5` for large databases |
| Missing `post_task` hook in `task.json` | `post_task.sh` never runs; verifier sees unmodified file | Verify `"post_task": "sh /sdcard/tasks/<task>/post_task.sh"` in `task.json` |

### Difference from Section 11 (Stateless App Reset)

Section 11's `am force-stop` is used to **reset app state** at setup time. Section 16's `am force-stop` in `post_task.sh` is used to **flush the SQLite WAL** at evaluation time. These are different hooks (`pre_task` vs `post_task`) with different purposes. A task may need both: `force-stop` in `setup_task.sh` to clear previous session data, and `force-stop` in `post_task.sh` to checkpoint WAL before copying the result.

---

## 17. Do Not Use `uiautomator dump` for SQLite-Based Apps

For apps that persist all agent work to a SQLite database (see Section 16), **skip `uiautomator dump` entirely** for verification. Querying the database directly is more reliable, complete, and unambiguous.

`uiautomator dump` is the right choice when:
- The app does NOT write to a local database (pure UI state only)
- Verification requires confirming what's currently visible on screen
- The app encrypts or obfuscates on-disk storage

For SQLite-backed apps, the database IS the ground truth — use it.
