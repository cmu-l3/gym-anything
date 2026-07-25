> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Linux Desktop Environment Patterns

## Overview

When the target environment is a Linux VM with a graphical desktop (the most common Gym-Anything environment type), several patterns differ from pure server-side or headless environments. This document consolidates the key patterns for task scripts, GUI interaction, verification, and testing in Linux desktop environments. It is the Linux counterpart to `08_windows_environment_patterns.md` and `09_android_environment_patterns.md`.

---

## 1. Scripts Are Bash, Running via SSH Hook in a Login Shell

Task hooks (`pre_task`, `post_task`) execute as:
```
sudo -E bash -lc <hook_cmd>
```

Key properties of this execution context:
- **Login shell** (`-l`): `/etc/profile` and `/etc/profile.d/*.sh` are sourced. Standard system PATH is available.
- **Not interactive**: `~/.bashrc` is NOT sourced. User aliases and functions defined there are unavailable.
- **Root user** (`sudo`): The hook runs as root, not as the desktop user (`ga`). GUI apps launched by root may have permission or XAuthority issues.
- **DISPLAY is not set**: The SSH session does not inherit the display server's DISPLAY variable. All GUI operations require an explicit `DISPLAY=:1` prefix.

```bash
#!/bin/bash
# Correct: always export DISPLAY before GUI operations
export DISPLAY=:1

# Correct: launch GUI apps as the desktop user, not root
su - ga -c "DISPLAY=:1 /opt/myapp/myapp &"

# Correct: test for window presence
DISPLAY=:1 wmctrl -l | grep -qi "My App Title"
```

---

## 2. GUI Application Launch Pattern

**Use `su - ga -c "DISPLAY=:1 app &"`, never bare `app &` from root.**

Running a GUI app as root from within a `sudo` context may fail with XAuthority errors. The canonical pattern:

```bash
# Launch as the desktop user with correct display
su - ga -c "DISPLAY=:1 /path/to/app --no-sandbox >> /home/ga/app.log 2>&1 &"

# Wait for the window to appear (don't rely on sleep alone)
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "AppWindowTitle"; then
        break
    fi
    sleep 2
done
```

**Do NOT use `setsid`** — `setsid` creates a new process session that may not inherit D-Bus or XAuthority correctly, causing the X11 app to start but immediately exit with a display error. Use plain `... &` or `nohup ... &`.

**For apps that require a login user environment** (PATH, home directory, dotfiles), use `su - ga -c "..."` (with the dash, which sources the user's login environment).

---

## 3. Confirming App Readiness: Window Presence, Not Process Existence

`pgrep -f appname` returns True as soon as the process starts, which may be long before the app window is visible. Heavy GUI apps (Qt, Electron, Java Swing) can take 15–60 seconds to fully load.

**Use `wmctrl -l | grep` as the readiness check:**

```bash
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "Window '$pattern' is visible"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Window '$pattern' not found after ${timeout}s"
    return 1
}

wait_for_window "MyApplication" 60
```

**Handle first-run dialogs**: Commercial apps often show license/EULA dialogs on first launch. Dismiss these in `post_start` (not `setup_task.sh`). See Lesson 44 in `05_learnings_best_practices.md` for the full pattern.

---

## 4. Screenshot Capture

Two tools are available; choose based on the compositor type:

```bash
# Option 1: scrot (works on most desktop environments without compositor)
DISPLAY=:1 scrot /tmp/screenshot.png 2>/dev/null

# Option 2: ImageMagick import (works with compositing window managers like GNOME/KWin)
DISPLAY=:1 import -window root /tmp/screenshot.png 2>/dev/null

# Option 3: gnome-screenshot (GNOME only)
DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    su - ga -c "gnome-screenshot -f /tmp/screenshot.png" 2>/dev/null
```

**Prefer `import -window root`** for GNOME-based desktops (`ubuntu-gnome-systemd` preset). `scrot` produces black screenshots on compositor-enabled desktops. See Lesson 123 in `05_learnings_best_practices.md`.

**Always add a sleep before capturing** to allow the UI to fully render:
```bash
sleep 2
DISPLAY=:1 import -window root /tmp/screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/screenshot.png 2>/dev/null || true
```

---

## 5. Database Access (MySQL/MariaDB)

For environments using a MySQL/MariaDB database running in a Docker container:

```bash
# Query pattern: -N suppresses header row, -B produces tab-separated output
RESULT=$(docker exec <mysql_container> mysql -u <user> -p<pass> <database> -N -B -e "SELECT ...")

# Find the actual container name (may differ from what you expect)
MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -1)
docker exec "$MYSQL_CONTAINER" mysql ...
```

**Key flags:**
- `-N`: No column headers
- `-B`: Batch mode (tab-separated output, no table borders)
- Parse fields with `cut -f1`, `cut -f2`, etc.

**Always check for empty results:**
```bash
RESULT=$(docker exec "$MYSQL_CONTAINER" mysql -u user -ppass db -N -B -e "SELECT ...")
if [ -z "$RESULT" ]; then
    echo "ERROR: Required record not found"
    exit 1
fi
```

---

## 6. Result JSON Path Convention for Linux

Store result JSON in `/tmp/` using task-specific names (see Lesson 164 in `05_learnings_best_practices.md`):

```
/tmp/<task_name>_result.json
```

In `verifier.py`:
```python
RESULT_PATH = "/tmp/<task_name>_result.json"
copy_from_env(RESULT_PATH, tmp.name)
```

**Baseline and ground-truth files** follow the same naming:
```
/tmp/<task_name>_initial_count      # baseline count at task start
/tmp/<task_name>_start_ts           # Unix timestamp at task start
/tmp/<task_name>_gt.json            # ground truth computed at setup time
```

---

## 7. Timestamp Recording and File Modification Checks

Record task start time as a Unix integer:
```bash
date +%s > /tmp/<task_name>_start_ts
```

In `export_result.sh`, compare file modification times using **integer** seconds (not floats) to avoid sub-second false positives (see Lesson 15 in `05_learnings_best_practices.md`):

```bash
TASK_START=$(cat /tmp/<task_name>_start_ts 2>/dev/null || echo "0")
FILE="/home/ga/Desktop/output.ext"

FILE_EXISTS=false
FILE_IS_NEW=false

if [ -f "$FILE" ]; then
    FILE_EXISTS=true
    # stat -c %Y returns mtime as integer seconds since epoch
    FILE_MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi
```

In `verifier.py`, also truncate to integer before comparing (defensive):
```python
import os
mtime = int(os.path.getmtime(local_file))  # cast to int
task_start = int(result.get('task_start', 0))
is_new = mtime > task_start
```

---

## 8. Script Structure Template

**`setup_task.sh`:**
```bash
#!/bin/bash
echo "=== Setting up <Task Name> ==="

# Source shared utilities (with fallback)
. /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if sourcing fails
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# STEP 1: Verify required data exists
# (query database or filesystem)

# STEP 2: Delete any stale output files that would contaminate the do-nothing test
# Remove items BEFORE recording the timestamp
rm -f /home/ga/Desktop/expected_output.ext 2>/dev/null || true

# STEP 3: Record baseline state
INITIAL_COUNT=$(...)
echo "$INITIAL_COUNT" > /tmp/<task_name>_initial_count

# STEP 4: Record task start timestamp (AFTER cleanup)
date +%s > /tmp/<task_name>_start_ts

# STEP 5: Ensure application is running
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "AppTitle"; then
    su - ga -c "DISPLAY=:1 /path/to/app &"
    sleep 10
fi

# STEP 6: Take initial screenshot
sleep 2
take_screenshot /tmp/<task_name>_start_screenshot.png

echo "=== Setup Complete ==="
```

**`export_result.sh`:**
```bash
#!/bin/bash
echo "=== Exporting <Task Name> Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/<task_name>_start_ts 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/<task_name>_initial_count 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/<task_name>_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/<task_name>_end_screenshot.png 2>/dev/null || true

# Query current state
CURRENT_COUNT=$(...)
NEW_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))

# Check output file
OUTPUT="/home/ga/Desktop/expected_output.ext"
FILE_EXISTS=false
FILE_IS_NEW=false
if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW=true
fi

cat > /tmp/<task_name>_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "new_count": $NEW_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW
}
EOF

echo "=== Export Complete ==="
```

---

## 9. Common Linux Desktop Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Missing `DISPLAY=:1` | `Cannot open display` or blank screenshot | Always prefix GUI commands with `DISPLAY=:1` |
| GUI app launched as root | XAuthority error, app exits immediately | Use `su - ga -c "DISPLAY=:1 app &"` |
| Using `setsid` with X11 app | Process starts, immediately exits | Remove `setsid`; use plain `... &` |
| `scrot` produces black image | Compositor is active (GNOME/KWin) | Use `import -window root` instead |
| `pgrep` says app running but window not visible | App still loading or first-run dialog blocking | Use `wmctrl -l | grep -qi "Title"` for readiness |
| Generic `/tmp/` file names | Multi-task baseline contamination | Use `/tmp/<task_name>_*` naming throughout |
| `chmod +x` skipped | Hook runs silently, exit code 126 | Always run `chmod +x tasks/<task>/*.sh` |
| App launched without `-`  in `su` | Wrong PATH, missing user environment | Use `su - ga -c "..."` (with dash) |
| Float mtime vs integer task_start | Stale file appears "new" (false positive) | Cast mtime to `int()` before comparison |
| `source` fails in `/bin/sh` shebang | `. /workspace/scripts/task_utils.sh` fails | Use `.` instead of `source`; ensure `#!/bin/bash` |

---

## 10. Evidence Collection for Linux Environments

```python
# In your test/evidence collection script
import os
from gym_anything.api import from_config

env = from_config("benchmarks/cua_world/environments/<env_name>", task_id="<task_name>")
obs = env.reset(seed=42, use_cache=True, cache_level="pre_start", use_savevm=True)

# Take screenshot
env._runner.exec_capture('DISPLAY=:1 import -window root /tmp/evidence.png 2>/dev/null || DISPLAY=:1 scrot /tmp/evidence.png 2>/dev/null')
env._runner.copy_from('/tmp/evidence.png', f'benchmarks/cua_world/environments/<env_name>/evidence_docs/<task_name>_screenshot.png')

# Check database / filesystem evidence
output = env._runner.exec_capture('docker exec <mysql_container> mysql -u user -ppass db -N -B -e "SELECT ..."')
print(output)

# Run export and print result
export_out = env._runner.exec_capture('bash -l /workspace/tasks/<task_name>/export_result.sh 2>&1')
print(export_out)
result_raw = env._runner.exec_capture('cat /tmp/<task_name>_result.json')
print(result_raw)

env.close()
```

---

## 11. XDG Config Directory Apps (File-Based State)

Many Linux desktop apps follow the [XDG Base Directory specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html), storing all persistent state in flat files rather than a database:

| XDG directory | Typical path | Used for |
|---|---|---|
| Config | `~/.config/<AppName>/` | User preferences, modules, named objects |
| Data | `~/.local/share/<AppName>/` | Saved projects, libraries, history |
| Cache | `~/.cache/<AppName>/` | Downloaded data, thumbnails, indices |

For these apps, the "scripting seam" (Phase 2 of `12_new_environment_onboarding.md`) is **Option C: Readable data files** — no database, no CLI required. `export_result.sh` reads the files directly; `verifier.py` receives the parsed values.

### Common config file formats

**INI / key=value with sections** (e.g., GPredict `.qth`, `.mod`, `.cfg`):
```bash
# Read a specific key from an INI file in export_result.sh
python3 << 'PYEOF'
import configparser, os, json

cfg = configparser.ConfigParser()
cfg.read(os.path.expanduser("~/.config/MyApp/settings.cfg"))

result = {
    "unit_system": cfg.get("MAIN", "unit", fallback=None),
    "utc_time":    cfg.get("MAIN", "utc",  fallback=None),
}
print(json.dumps(result))
PYEOF
```

**Flat key=value without section headers** (many Qt apps):
```bash
# Wrap in a fake section header so configparser can handle it
python3 << 'PYEOF'
import configparser, io, os, json

raw = open(os.path.expanduser("~/.config/MyApp/prefs")).read()
cfg = configparser.ConfigParser()
cfg.read_string("[DEFAULT]\n" + raw)

result = {"theme": cfg.get("DEFAULT", "theme", fallback=None)}
print(json.dumps(result))
PYEOF
```

**Semicolon/comma-delimited lists in a single field** (common for multi-select settings):
```bash
python3 << 'PYEOF'
import configparser, os, json

cfg = configparser.ConfigParser()
cfg.read(os.path.expanduser("~/.config/MyApp/module.mod"))

raw_list = cfg.get("MODULE", "ITEMS", fallback="")
# Split on semicolons; filter empty strings
items = [x.strip() for x in raw_list.split(";") if x.strip()]

print(json.dumps({"items": items, "item_count": len(items)}))
PYEOF
```

### Verification strategy for XDG config apps

Because the state is in files, not a database, verification is simpler than for database-backed apps:

1. **`export_result.sh`**: Read the relevant config files and output their key fields as JSON to `/tmp/<task_name>_result.json`. Scan all files matching a pattern (e.g., `~/.config/App/*.station`) using Python's `os.listdir` loop.
2. **`verifier.py`**: Copy the JSON from the VM with `copy_from_env`, parse it, and check values. For coordinates, use proximity matching (Pattern 16 in `03_verification_patterns.md`). For filenames the agent may have chosen freely, use scan-by-content (Pattern 17).

### Pitfalls specific to XDG config apps

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| App writes config only on clean exit | Config file missing or stale after `killall` | Terminate app gracefully (`wmctrl -ic <wid>` → wait → `kill`) before running export |
| Config directory doesn't exist yet | `FileNotFoundError` in export script | Create dir in `setup_task.sh` with `mkdir -p ~/.config/MyApp/` |
| App uses XDG_CONFIG_HOME override | Files in unexpected location | Check `printenv XDG_CONFIG_HOME`; fall back to `~/.config/<App>` |
| INI file has no section header | `configparser.MissingSectionHeaderError` | Prepend a `[DEFAULT]` header before parsing (see "flat key=value" example above) |
| List field contains trailing delimiter | `["25544", "27607", ""]` after split | Always filter with `if x.strip()` after splitting |
