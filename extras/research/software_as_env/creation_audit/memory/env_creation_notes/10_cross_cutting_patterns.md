# Cross-Cutting Patterns & Lessons Learned

Distilled from 100+ environment implementations. These are generalizable patterns that apply to any new environment, not just the specific app where they were discovered. **37 patterns total.**

**See also:** `11_windows_environments.md` for Windows-specific patterns (schtasks, PyAutoGUI, Office installs). `12_macos_environments.md` for macOS-specific patterns (use.computer runner, SIP read-only root, Rosetta, TCC over SSH).

---

## 1. Service Readiness Polling Is Non-Negotiable

**Never assume a service is ready after starting it.** Always poll with retries and a timeout.

- Canvas LMS had a **67% task failure rate** before adding health-check polling
- Splunk's REST API (port 8089) starts *after* the web UI (port 8000) — checking the wrong port gives false positives
- Oracle Database needs 2-5 minutes for initialization
- Docker containers report "running" before the app inside is actually ready

**Pattern:** Add a readiness loop in `post_start` or `pre_task`:
```bash
# Web apps
for i in $(seq 1 60); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null)
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ] || [ "$STATUS" = "303" ]; then
    break
  fi
  sleep 2
done

# Databases
for i in $(seq 1 30); do
  docker exec db-container mysql -u root -ppass -e "SELECT 1" 2>/dev/null && break
  sleep 2
done
```

**Affected envs:** Canvas LMS, Splunk, Oracle, Moodle, Magento, Odoo, Jenkins, DHIS2, OpenProject, REDCap, WooCommerce

---

## 2. Two-Layer Dialog Suppression

**Config files alone are never enough.** Almost every GUI app shows first-run dialogs despite pre-created config files.

**Layer 1 — Pre-create config/prefs before first launch:**
```bash
# Example: LibreOffice
mkdir -p ~/.config/libreoffice/4/user/
cat > ~/.config/libreoffice/4/user/registrymodifications.xcu << 'EOF'
...suppress tips, updates, etc...
EOF
```

**Layer 2 — Runtime dismissal after launch:**
```bash
# Example: xdotool dismiss
sleep 5
WID=$(xdotool search --name "Welcome" 2>/dev/null | head -1)
[ -n "$WID" ] && xdotool key --window "$WID" Escape
```

**Best practice — Warm-up launch in `post_start`:**
Launch the app, wait for it to appear, dismiss dialogs, kill it. This clears first-run state so that the actual task launch is clean. Used successfully in: Power BI, SNAP, Firefox, BlueMail, OpenToonz, Thunderbird, Docker Desktop, IntelliJ, Eclipse, and many others.

---

## 3. Process Detection by Full Binary Path

Generic process names always collide with something else.

| App | Wrong | Right |
|-----|-------|-------|
| SNAP (ESA) | `pgrep snap` | `pgrep -f /opt/snap/jre/bin/java` |
| Screaming Frog | `pgrep screaming` | `pgrep -fi screamingfrogseospider` |
| 3D Slicer | `pgrep Slicer` | `pgrep -f /opt/Slicer/bin/SlicerApp-real` |

**Rule:** Always use `pgrep -f /full/path/to/binary` in scripts. Never rely on short process names.

---

## 4. Snap Package Gotchas

Snap-installed apps behave differently from native installs in several ways:

- **Profile/data paths differ** — snap apps store data under `~/snap/<app>/` not `~/.config/`
- **Firefox snap has NO `--profile` flag** — must inject `user.js` into the default profile after a warm-up launch
- **Some apps require `--classic` confinement** — DBeaver, Azure Data Studio, others will fail without it
- **Name conflicts** — ESA SNAP vs Ubuntu snapd. Solution: use `sys.symlinkDir=/usr/local/bin/snap-esa`
- **Snap apps can't access arbitrary paths** — they're sandboxed. Put data in `~/` or `/tmp/`

---

## 5. Database Verification >> Screenshot Verification (for Web Apps)

For every web application environment, querying the database directly is far more reliable than screenshot-based verification.

```bash
# Deterministic — always works
docker exec moodle-mariadb mysql -u moodleuser -ppass moodle \
  -e "SELECT id, fullname FROM mdl_course WHERE shortname='CS101'"

# Flaky — depends on rendering, timing, resolution
# (screenshot of the Moodle course page)
```

**Use DB queries as primary signal, VLM screenshots as secondary confirmation.**

Applies to: Moodle, Canvas, Odoo, WordPress, WooCommerce, Magento, OpenSIS, Snipe-IT, Vtiger, OpenProject, Drupal, DHIS2, REDCap, openMAINT, Mirth Connect, and every other web app.

---

## 6. "Do Nothing" Must Provably Fail

Naive verification checks often pass even when the agent does nothing:

- "Screenshot file > 100KB" — the welcome screen is already >100KB (3D Slicer)
- "Window titled X exists" — it existed before the task started (Blender)
- "Output file exists" — leftover from a previous run

**Robust verification requires:**
- **Timestamp/modification-time deltas** — file must be newer than task start
- **Count changes** — number of items before vs after (e.g., `slicer.mrmlScene.GetNodesByClass()`)
- **Content-specific checks** — file contains expected data, not just exists
- **Multi-signal AND-ing** — all criteria must pass, not just one (never OR)
- **Hybrid scoring** — 70% programmatic + 30% VLM (or similar weighting)

**Affected envs:** Blender, AstroImageJ, 3D Slicer, WordPress, GeoGebra, QGIS

---

## 7. Download URLs Are Fragile — Always Have Fallbacks

CDN URLs change, GitHub release URLs shift, vendor sites restructure. Every environment that downloads software at install time should use a fallback chain:

```bash
# Try primary, then fallback, then cached
URL1="https://cdn.vendor.com/app-v2.3.deb"
URL2="https://github.com/vendor/app/releases/download/v2.3/app.deb"
URL3="https://mirror.example.com/cached/app-v2.3.deb"

for url in "$URL1" "$URL2" "$URL3"; do
  wget -q "$url" -O /tmp/app.deb && break
done
```

**Affected envs:** IntelliJ, AstroImageJ, DaVinci Resolve, Eclipse, Screaming Frog, RStudio

---

## 8. Docker Hub Rate Limits — Always Authenticate Before Pulling

Anonymous Docker Hub pulls are rate-limited (~100 pulls/6hr per IP). On shared compute infrastructure this limit is hit constantly, causing `docker compose pull` to fail with `429 Too Many Requests`.

**Always authenticate before pulling in every Docker-based environment:**

```bash
# In post_start hook, before docker compose pull
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi
docker compose pull
```

**The credentials file already exists** at `benchmarks/cua_world/environments/idempiere_env/config/.dockerhub_credentials`. When creating a new Docker-based environment, **copy it**:

```bash
cp benchmarks/cua_world/environments/idempiere_env/config/.dockerhub_credentials benchmarks/cua_world/environments/<your_env>/config/.dockerhub_credentials
```

The file contains:
```bash
DOCKERHUB_USERNAME="hackear2041"
DOCKERHUB_TOKEN="dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g"
```

The file is gitignored (`.dockerhub_credentials` in `.gitignore`). Do not create a new/different credentials file — always copy from the reference location above.

This pattern is in `07_web_applications_docker.md` and must be used in **all new Docker-based environments**.

**Affected envs:** All Docker-in-QEMU environments — iDempiere, Snipe-IT, OrangeHRM, Wazuh, Redmine, OpenMRS, Vtiger, SuiteCRM, Rocket.Chat, etc.

---

## 9. Docker Compose v2, Not v1 (with Exception)

Docker Compose v1 (`docker-compose` binary) has known bugs including `KeyError: 'ContainerConfig'`. Always use v2 (`docker compose` as a Docker subcommand) — **except Bahmni, which requires v1**.

```bash
# Wrong — v1, may fail
docker-compose up -d

# Right — v2
docker compose up -d
```

If the VM image has v1 pre-installed, install v2 in `pre_start`:
```bash
sudo apt-get install -y docker-compose-plugin
```

**Exception — Bahmni requires v1 (1.29.2):**
```bash
pip3 install docker-compose==1.29.2
# Then use: docker-compose up -d  (with hyphen)
```

Check app docs: if they show `docker-compose` (hyphenated), they may require v1. See also pattern #27.

---

## 10. File Permissions After `docker cp` or Volume Mounts

Apps inside containers run as non-root UIDs. After copying files in, always fix ownership:

| App | Container user | Fix |
|-----|---------------|-----|
| Snipe-IT | `docker` (uid=10000, gid=50) | `chown 10000:50` |
| WordPress | `www-data` (uid=33) | `chown 33:33` |
| Moodle | `www-data` | `chown www-data:www-data` |

```bash
docker cp config.php container:/var/www/html/
docker exec container chown www-data:www-data /var/www/html/config.php
```

---

## 11. Copy-Before-Query for Locked SQLite Databases

Firefox, Thunderbird, and other apps hold WAL locks on their SQLite databases while running. Querying the live file will either fail or return stale data.

```bash
# Wrong — database is locked
sqlite3 ~/.mozilla/firefox/profile/places.sqlite "SELECT ..."

# Right — copy first, then query
cp ~/.mozilla/firefox/profile/places.sqlite /tmp/places_copy.sqlite
cp ~/.mozilla/firefox/profile/places.sqlite-wal /tmp/places_copy.sqlite-wal 2>/dev/null
sqlite3 /tmp/places_copy.sqlite "SELECT ..."
```

Alternative: close the app before querying, then reopen if needed.

---

## 12. Here-Documents for SQL/Scripts with Special Characters

Piping SQL through shell arguments causes escaping nightmares. Use here-documents:

```bash
docker exec -i oracle-xe sqlplus hr/hr@XEPDB1 << 'EOSQL'
SELECT employee_id, first_name || ' ' || last_name AS name
FROM employees
WHERE salary > 10000
ORDER BY salary DESC;
EOSQL
```

The single-quoted `'EOSQL'` delimiter prevents shell variable expansion inside the heredoc.

---

## 13. IDE Environments: EULA Bypass + Version-Specific Config Dirs

All JetBrains IDEs (IntelliJ, PyCharm) share the same patterns:

- **EULA bypass:** Add `-Djb.privacy.policy.text=<!--999.999-->` to `.vmoptions`
- **Config dirs are version-stamped:** `~/.config/JetBrains/IdeaIC2024.3/` — detect version dynamically from `build.txt`
- **Trusted paths:** Pre-create `trusted-paths.xml` to avoid "Trust this project?" dialog
- **Dependency pre-warming:** Run `mvn dependency:resolve` in `post_start` so tasks don't wait for downloads

Eclipse has its own variant: suppress workspace selection dialog, pre-create `.project`/`.classpath` metadata.

---

## 14. Warm-Up Launch Pattern

The single most reusable pattern across all GUI environments. Put this in `post_start`:

```bash
# 1. Launch the app
DISPLAY=:1 /path/to/app &
APP_PID=$!

# 2. Wait for window to appear
for i in $(seq 1 30); do
  WID=$(xdotool search --name "AppName" 2>/dev/null | head -1)
  [ -n "$WID" ] && break
  sleep 1
done

# 3. Dismiss any first-run dialogs
xdotool key Escape
sleep 2

# 4. Kill the app
kill $APP_PID 2>/dev/null
wait $APP_PID 2>/dev/null
```

After this, subsequent launches will be clean (no first-run dialogs).

---

## 15. Hybrid Verification Scoring

Pure programmatic verification misses visual state. Pure VLM is unreliable and gameable. The best practice is a weighted hybrid:

- **70% programmatic** — file parsing, DB queries, API calls, content checks
- **30% VLM** — screenshot analysis confirms visual state matches expectations

**Rules:**
- Programmatic criteria use AND-logic (all must pass)
- VLM acts as a sanity-check confirmation, not the primary signal
- "Do nothing" scenario must score 0 on programmatic checks
- Require exact matches for critical fields (names, IDs), fuzzy for layout

**Affected envs:** WordPress, Blender, AstroImageJ, 3D Slicer, GeoGebra, LibreOffice Writer

---

## 16. Use Real Public Datasets, Not Synthetic Data

Synthetic/handwritten data creates unrealistic toy scenarios. Use well-known public datasets:

| Domain | Dataset | Used In |
|--------|---------|---------|
| Digital media store | Chinook DB | DBeaver |
| SEO crawling | crawler-test.com | Screaming Frog |
| CMS content | WordPress Theme Unit Test | WordPress |
| 3D scenes | Blender Foundation demos (BMW, classroom) | Blender |
| SQL Server | AdventureWorks2022 | MS SQL Server |
| Email | SpamAssassin public corpus | Thunderbird, BlueMail |
| Medical imaging | MRHead.nrrd, pydicom samples | 3D Slicer, Weasis |
| Astronomy | NASA FITS (WFPC2, UIT) | AstroImageJ |
| HR/ERP | Oracle HR schema (107 employees) | Oracle DB |

---

## 17. Coordinate Scaling for VLM-Based Automation

VLM (ask_cua.py) returns coordinates normalized to **1280x720**. The actual VM resolution may differ.

```python
# Scale from VLM coordinates to actual resolution
actual_x = vlm_x * (actual_width / 1280)
actual_y = vlm_y * (actual_height / 720)

# Common case: 1920x1080 display
actual_x = vlm_x * 1.5
actual_y = vlm_y * 1.5
```

Always confirm the VM's actual resolution before hardcoding click coordinates in automation scripts.

---

## 18. `setsid` Is Required for GUI Apps Launched from SSH

SSH creates a process group. When SSH disconnects or the session exits, the kernel sends SIGHUP to the entire process group — killing any GUI apps launched in that group.

**Problem:** `DISPLAY=:1 /path/to/app &` — app dies when SSH command returns.

**Fix:** Always use `setsid` to detach the process from the SSH session:
```bash
setsid DISPLAY=:1 /path/to/app > /tmp/app.log 2>&1 &
# or via su
su - ga -c "setsid DISPLAY=:1 /path/to/app > /tmp/app.log 2>&1 &"
```

This also means the app continues running after `post_start` finishes, which is required for warm-up launches.

**Affected envs:** JASP, MedinTux (Wine), gvSIG, Jamovi, virtually all GUI apps launched from hooks.

---

## 19. `pgrep -a -f` Self-Match Bug

`pgrep -a -f pattern` lists matching processes with full command lines. If the pattern string appears in the pgrep command itself, it self-matches and reports the wrong count.

**Example of the bug:**
```bash
# This matches the pgrep process itself if it's checking for "wine"
if pgrep -a -f wine > /dev/null; then  # BUG: may self-match
    echo "RUNNING"
fi
```

**Fixes:**
```bash
# Fix 1: Use count mode (-c) — reports 0 if only self-match
COUNT=$(pgrep -c -f wine 2>/dev/null || echo 0)
[ "$COUNT" -gt 0 ] && echo "RUNNING"

# Fix 2: Use full binary path (doesn't appear in pgrep's own cmdline)
pgrep -f /opt/my-app/bin/app

# Fix 3: Exclude the grep process explicitly
pgrep -f wine | grep -v "$$"
```

**Affected envs:** MedinTux, any script that uses pgrep for status detection.

---

## 20. XAUTHORITY Must Be Set Explicitly for Cross-User X11

When a script runs as root (or a different user) but needs to interact with an X11 display owned by another user, the `~/.Xauthority` cookie file is often wrong or empty.

**Common failure patterns:**
- `~/.Xauthority` exists but has 0 bytes when accessed via SSH (not the interactive session's file)
- GNOME manages Xauthority at a non-standard path

**Known working paths by system:**
| System | Correct XAUTHORITY |
|--------|-------------------|
| Bahmni (GNOME) | `/run/user/1000/gdm/Xauthority` |
| Standard GNOME | `/home/ga/.Xauthority` (only if SSH into same session) |
| Direct X session | `/home/ga/.Xauthority` |

**Pattern for all root-context X11 commands:**
```bash
# Always set both DISPLAY and XAUTHORITY explicitly
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 500 300 click 1

# Or export at script top
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
```

**Also applies to:** `scrot`, `import`, `xwd`, `wmctrl`, `xdotool` — all X11 tools fail silently with wrong XAUTHORITY.

**Affected envs:** Bahmni, FreeCAD, Redmine, GCompris.

---

## 21. Shell Expansion of `$` in Passwords and Hashes

Passwords, bcrypt hashes, and API keys frequently contain `$` characters. Shell double-quotes expand `$var`, silently corrupting the value.

**Common failure:** bcrypt hash `$2y$10$abc...` becomes `$2y0abc...` in double-quoted string.

**Fixes:**
```bash
# Fix 1: Generate hash INSIDE docker exec (no shell expansion)
docker exec app-container php -r '
$hash = password_hash("Admin1234!", PASSWORD_BCRYPT, ["cost" => 12]);
echo $hash;
'

# Fix 2: Single quotes for literal strings
HASH='$2y$10$abc...'  # single quotes = literal, no expansion

# Fix 3: Escape each $ with backslash
HASH="\$2y\$10\$abc..."
```

**Characters that cause issues:** `$`, `` ` ``, `\`, `!` (in some shells).

**Affected envs:** OrangeHRM, GNU Health, any env setting bcrypt/scrypt passwords via shell.

---

## 22. Session Cookies Cannot Be Injected via `cookies.sqlite`

Modern web applications store session cookies in memory, not in `cookies.sqlite`. Modifying the SQLite file while the browser is running has no effect on the live session.

**What doesn't work:**
```python
# This does NOT inject a session into a running browser
conn = sqlite3.connect('~/.mozilla/firefox/profile/cookies.sqlite')
conn.execute("INSERT INTO moz_cookies VALUES (...session_cookie...)")
```

**What works:** Use the browser UI to log in (xdotool automation):
```bash
# Navigate to login page, type credentials, submit
xdotool type --window $WID "$USERNAME"
xdotool key Tab
xdotool type --window $WID "$PASSWORD"
xdotool key Return
```

For repeated logins across tasks, put a `ensure_logged_in()` function in `task_utils.sh` and call it at the start of each pre_task hook.

**Affected envs:** Redmine, VistA VEHU, any env where session-based auth is needed per task.

---

## 23. `pre_start` Timeout — Background Continuation with Marker Files

Some applications require very long installs (15+ minutes). The gym_anything framework has hook timeouts. The pattern to handle this:

**Pattern:**
```bash
# In pre_start.sh — start long install in background, return quickly
install_long_app() {
    # ... 15-minute installation ...
    touch /tmp/install_complete.marker
}

# Start in background, detach from parent
nohup bash -c 'install_long_app' > /tmp/install.log 2>&1 &
echo "Install started in background (PID: $!)"
# pre_start returns immediately — hook doesn't time out
```

```bash
# In post_start.sh — wait for marker before proceeding
echo "Waiting for installation to complete..."
TIMEOUT=900  # 15 minutes
ELAPSED=0
while [ ! -f /tmp/install_complete.marker ]; do
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: Installation timed out"
        exit 1
    fi
done
echo "Installation complete, proceeding..."
```

**Affected envs:** GNU Health (15min trytond install), Oracle Database (10min init), Magento.

---

## 24. Subshell Stdout Pollution — Use `>&2` for Status Messages

When capturing output via command substitution (`VAR=$(func)`), **any `echo` inside `func` goes into `VAR`**, not to the terminal. This pollutes the variable with diagnostic text.

**The bug:**
```bash
get_uuid() {
    echo "Calling API..."   # BUG: this goes into UUID variable!
    curl -s http://api/endpoint | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])"
}
UUID=$(get_uuid)
# UUID is now "Calling API...\nactual-uuid-value"
```

**The fix:**
```bash
get_uuid() {
    echo "Calling API..." >&2   # Redirect status to stderr (visible on terminal, not captured)
    curl -s http://api/endpoint | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])"
}
UUID=$(get_uuid)
# UUID is now "actual-uuid-value" ✓
```

**Rule:** Every function that might be called via `$(...)` must redirect all diagnostic output to `>&2`.

**Affected envs:** OpenMRS O3 (`extract_uuid()`), any env with REST API UUID extraction.

---

## 25. `set -euo pipefail` Breaks `source task_utils.sh`

`set -euo pipefail` is excellent for error detection in standalone scripts, but breaks shared utility sourcing:

- `set -e` exits immediately on any non-zero return, including common patterns in task_utils.sh
- `set -u` fails on unset variables that may be intentionally unset in the shared utility
- If task_utils.sh has any command that returns non-zero (even `grep` finding no match), the entire script exits

**Affected pattern:**
```bash
#!/bin/bash
set -euo pipefail  # BAD for setup_task.sh files
source /workspace/scripts/task_utils.sh  # May exit here if task_utils.sh has any failure
```

**Fix for setup_task.sh:**
```bash
#!/bin/bash
# Do NOT use set -euo pipefail in setup_task.sh files that source shared utils
# Use explicit error handling instead:
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }
```

**OK to use in:** standalone install scripts (`pre_start.sh`, `post_start.sh`) that don't source shared utilities.

**Affected envs:** Bahmni (explicitly documented), many others.

---

## 26. `unzip` Interactive Prompt Hangs SSH Sessions

`unzip archive.zip` to a directory with existing files prompts interactively:
```
replace existing_file? [y]es, [n]o, [A]ll, [N]one, [r]ename:
```
This blocks the SSH session indefinitely, causing hook timeouts.

**Always use overwrite flag:**
```bash
# Wrong — will hang if target files exist
unzip archive.zip -d /target/dir/

# Right — quiet + overwrite without asking
unzip -qo archive.zip -d /target/dir/

# Alternative: delete target first
rm -rf /target/dir/ && unzip -q archive.zip -d /target/dir/
```

**Related:** Never download multiple zip files to the same directory if their contents overlap (SolveSpace `box-parts.zip` and `box-asm.zip` share files).

---

## 27. Screenshot Tool Selection by Compositor

Different screenshot tools work/fail depending on the display compositor:

| Tool | GNOME compositor | No compositor |
|------|-----------------|---------------|
| `scrot` | ❌ Black image | ✓ Works |
| `import -window root` | ❌ Black image | ✓ Works |
| `xwd -id <WID>` | ✓ Works | ✓ Works |
| VNC screenshot (Python) | ✓ Works | ✓ Works |

**Rule for GNOME environments:**
```bash
# Capture a specific window (always reliable)
WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --class Epiphany | tail -1)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xwd -id $WID -out /tmp/ss.xwd
convert /tmp/ss.xwd /tmp/ss.png

# Or use VNC screenshot (most reliable overall)
# See gym_anything.runtime.runners.vnc_utils.VNCConnection
```

**Affected envs:** Bahmni (xwd required), SolveSpace (import -window root), LibreCAD (import -window root).

---

## 28. Windows: `schtasks /IT` Required for All GUI Apps from SSH

SSH in Windows runs in **Session 0** (the service session). Session 0 has no display. Any GUI app launched from Session 0 creates a window that's invisible to VNC/RDP and to the user.

**This is non-negotiable for ALL Windows GUI environments.**

```powershell
# WRONG — launches in Session 0, no visible window
Start-Process "C:\Program Files\App\app.exe"

# RIGHT — use schtasks with /IT to run in interactive session
$time = (Get-Date).AddMinutes(1).ToString("HH:mm")
schtasks /Create /SC ONCE /IT /TR "C:\path\to\app.exe" /TN "LaunchApp" /ST $time /F
Start-Sleep -Seconds 65
schtasks /Delete /TN "LaunchApp" /F 2>$null
```

**Important subtleties:**
- Always use dynamic `/ST` time: `(Get-Date).AddMinutes(1).ToString("HH:mm")` — never hardcode `/ST 00:00`
- Set `$ErrorActionPreference = "Continue"` before schtasks (strict mode treats stderr as fatal)
- Use `/F` to force overwrite existing task names

**Affected envs:** All Windows environments — Power BI, NinjaTrader, Office 2010, Visual Studio 2022, Copper POS.

---

## 29. Windows Automation: Win32 API Clicks vs PyAutoGUI

Win32 API mouse simulation (`SetCursorPos` + `mouse_event`) does NOT work for all applications. Some apps ignore synthetic input from this method.

**Known non-working apps:** NinjaTrader, Copper POS (NCH Software).

**Fallback: PyAutoGUI TCP server** — deploy a Python socket server on the VM that accepts commands:
```powershell
# In post_start — start PyAutoGUI TCP server on port 5555
python3 -c "
import socket, json, pyautogui
# ... socket server loop receiving {action, x, y} commands
"
```

```python
# In setup_task.ps1 — send commands to PyAutoGUI server
function Send-PyAutoGUI($cmd) {
    $client = New-Object System.Net.Sockets.TcpClient("localhost", 5555)
    # ... send JSON command
}
```

**Decision tree:**
1. Try VNC clicks (simplest)
2. If that fails, try Win32 API (`SetCursorPos` + `mouse_event`)
3. If that fails, use PyAutoGUI TCP server

**Affected envs:** NinjaTrader, Copper POS.

---

## 30. PowerShell Strict Mode + Native Commands

`Set-StrictMode -Version Latest` in PowerShell causes native command stderr output to throw **terminating errors**, even when the command succeeds.

```powershell
Set-StrictMode -Version Latest  # Dangerous with native commands

# This FAILS even though msiexec succeeds (msiexec writes to stderr):
msiexec /qn /i "app.msi"  # → "The term 'NativeCommandError' is not..."
```

**Fixes:**
```powershell
# Fix 1: Suppress stderr for specific commands
msiexec /qn /i "app.msi" 2>$null

# Fix 2: Temporarily lower error preference
$ErrorActionPreference = "Continue"
msiexec /qn /i "app.msi"
$ErrorActionPreference = "Stop"

# Fix 3: Don't use Set-StrictMode in scripts with native commands
# Use it only in pure PowerShell sections
```

**Affected envs:** All Windows environments using PowerShell install scripts.

---

## 31. Verify DB State After Every Seeding Operation — Never Trust `|| true`

**The problem:** Setup scripts commonly append `|| true` to suppress errors from seed INSERTs. But some databases have NOT NULL columns with no defaults that aren't obvious from documentation. An INSERT silently fails, `|| true` hides the error, and the task starts with wrong initial state.

```bash
# BAD — INSERT fails silently if drugs table has NOT NULL cols with no defaults
oscar_query "INSERT INTO drugs (demographic_no, GN, BN, dosage)
VALUES ('$PATIENT_NO', 'Amiodarone', 'Cordarone', '200mg');" 2>/dev/null || true
# No indication of failure — initial_drug_count recorded as 0 instead of 1
```

**Two root causes to guard against:**
1. **Hidden NOT NULL columns** — run `SHOW CREATE TABLE` or `DESCRIBE` before writing any INSERT to find them
2. **Wrong column names** — DB PKs are not always `id`; never assume — verify with `DESCRIBE tablename`

**Fix — always echo a count verification after seeding:**
```bash
# RIGHT — seed using SELECT FROM to carry existing column values
db_query "INSERT INTO drugs (...)
SELECT d.demographic_no, ..., 0, 0   -- include all NOT NULL cols with safe defaults
FROM patient_table d WHERE d.name='Patient Name';" 2>/dev/null || true

# CRITICAL: immediately verify the INSERT worked
DRUG_COUNT=$(db_query "SELECT COUNT(*) FROM drugs WHERE demographic_no='$PATIENT_NO'")
echo "Seeded drug count: $DRUG_COUNT (expected: 1)"
if [ "${DRUG_COUNT:-0}" -eq 0 ]; then
    echo "ERROR: Drug seeding failed — task cannot proceed correctly"
    exit 1
fi
```

**General rule:** After every `INSERT`, `UPDATE`, or `DELETE` in setup_task.sh, query the row count and log it. If the expected data isn't there, fail loudly (`exit 1`) rather than silently continuing with corrupt state.

**Affected envs:** OSCAR EMR (`drugs` table has `position INT NOT NULL`, `dispenseInternal TINYINT NOT NULL`), any relational DB environment.

---

## 32. Verifier Partial-Credit Fallbacks Must Use Deltas Against Baseline, Not Absolute Counts

**The problem:** When setup seeds initial data (e.g., one drug as a precondition), a verifier fallback like `current_count >= 1` fires on do-nothing — because the seeded data already satisfies the condition. This gives a do-nothing agent unearned partial credit.

**Example of the bug:**
```python
# BAD — setup seeds Amiodarone (1 drug); do-nothing gets 10pts because count >= 1
elif result.get('current_active_drugs', 0) >= 1:
    score += 10
    feedback.append("A medication was added but not confirmed by name")
```

**The fix — always compare against the recorded baseline:**
```python
# GOOD — only fires if agent added a NEW drug beyond what was seeded
elif result.get('current_active_drugs', 0) > result.get('initial_drug_count', 0):
    score += 10
    feedback.append("A medication was added but not confirmed by name")
```

**General rule:** Any verifier criterion that uses a count or existence check must be phrased as a **delta** — `current > initial` — whenever setup_task.sh seeds data for that same table/field. The `initial_*` baseline must be:
1. Recorded by setup_task.sh **after** all seeding is complete
2. Written to a temp file (e.g., `/tmp/initial_drug_count_<task>`)
3. Read by export_result.sh and included in the result JSON
4. Used by the verifier as the denominator for all delta comparisons

**This pattern applies to:** medications, allergies, notes, measurements, appointments, attachments, tickets — any entity that setup seeds as a precondition.

**Affected envs:** OSCAR EMR (`medication_review_and_allergy`), any env where setup seeds entities the agent must create/modify.

---

## 33. Three-Test Verifier Validation (Required Quality Gate)

Every verifier must pass three anti-gaming tests before a task is considered complete. These are **not** about simulating agent behavior — they validate the verifier's own correctness and resistance to gaming.

**The three required tests:**

| Test | Method | Expected result |
|------|--------|-----------------|
| **Do-Nothing** | `env.reset()` + `env.step([], mark_done=True)` | `score == 0` |
| **Wrong-Target** | Inject null/unchanged-baseline result JSON, then call verifier | `score == 0` |
| **Partial Completion** | Inject partial result JSON (only some subtasks done) | `0 < score < pass_threshold` |

**Do-nothing test** — use the framework directly:
```python
env = from_config("benchmarks/cua_world/environments/<env>", task_id="<task>@1")
obs = env.reset(seed=42, use_cache=True, cache_level="post_start", use_savevm=True)
obs, reward, done, info = env.step([], mark_done=True)
result = info.get("verifier", {})
assert result.get("score", -1) == 0, f"Do-nothing gave score={result.get('score')}"
```

**Wrong-target/partial tests** — inject a crafted result JSON file, then call the verifier through `env.step([], mark_done=True)`:
```python
# Since export_result.sh (post_task hook) runs as root, /tmp/task_result.json is owned by root.
# SFTP write from the 'ga' user fails with PermissionError.
# Use sudo python3 stdin injection instead:

def inject_result(ssh_client, task_name, payload):
    json_bytes = json.dumps(payload, indent=2).encode()
    transport = ssh_client.get_transport()
    channel = transport.open_session()
    channel.settimeout(None)
    dest = f"/tmp/{task_name}_result.json"
    channel.exec_command(
        f"sudo python3 -c \"import sys; open('{dest}', 'wb').write(sys.stdin.buffer.read())\""
    )
    channel.sendall(json_bytes)
    channel.shutdown_write()
    channel.recv_exit_status()
    channel.close()
```

**Wrong-target payload design**: simulate the scenario where the agent edits the *wrong* object. Export_result.sh should query by specific name/ID, so the wrong object won't appear — the correct target is simply not found and has null/baseline values. A good wrong-target payload is the same as the do-nothing (unchanged baseline):
```python
WRONG_TARGET = {
    "task": "update_operator",
    "operator": {
        "company_full_name": "CorrectTarget Inc.",
        "operator_type": 0,      # unchanged from baseline
        "authorized_activities": ["photographing"],  # unchanged
    },
    "error": None
}
```

**Partial payload design**: complete only some subtasks (enough to score >0 but not enough to pass):
```python
PARTIAL = {
    "task": "register_aircraft_chain",
    "aircraft_model": {"name": "Nile Scout 200", "category": 2},  # done
    "aircraft_assembly": None,  # NOT done
    "aircraft": None,           # NOT done
    "error": None
}
# Expected: aircraft_model earns partial points; assembly+aircraft give 0 → total below pass threshold
```

**Wrong-target protection in export_result.sh**: The anti-gaming guarantee is only as good as the export script. Export scripts must query by the **expected specific name or ID** hardcoded in the task, not by "most recently created" or "any object of this type". This ensures that editing the wrong object leaves the result at the unchanged baseline.

**Affected envs:** All environments — this is a universal quality gate for every task's verifier.

---

## 34. Paramiko `exec_command(timeout=N)` Is Per-Read, Not Per-Command

`paramiko.Channel.exec_command()` does **not** accept a `timeout` parameter for total execution time. The `settimeout(N)` on a channel sets the *socket receive timeout* — i.e., how long to wait for the next packet of stdout/stderr. For scripts that run silently (no output) for longer than N seconds, this raises `socket.timeout` (or `paramiko.buffered_pipe.PipeTimeout`) even though the script is still running normally.

**The bug:**
```python
# BUG: setup_task.sh runs silently for 45s, timeout=30 → raises PipeTimeout at ~30s
stdin, stdout, stderr = ssh.exec_command("sudo bash /workspace/scripts/setup.sh", timeout=30)
stdout.read()  # raises socket.timeout before script finishes
```

**The fix — use a raw channel with `settimeout(None)` and poll for exit status:**
```python
transport = ssh.get_transport()
channel = transport.open_session()
channel.settimeout(None)          # no per-read timeout — block until data arrives
channel.exec_command("sudo bash /workspace/scripts/setup.sh")

# Poll for completion (channel.recv_exit_status() blocks until done)
exit_status = channel.recv_exit_status()
output = b""
while channel.recv_ready():
    output += channel.recv(4096)
channel.close()
```

**Alternative for scripts with output:** If the script produces output, read in a loop:
```python
channel.exec_command("sudo bash /workspace/scripts/setup.sh")
output = b""
while not channel.exit_status_ready():
    if channel.recv_ready():
        output += channel.recv(4096)
    time.sleep(0.1)
output += channel.recv(65536)  # drain remaining
exit_status = channel.recv_exit_status()
```

**Rule:** Never use `exec_command(..., timeout=N)` for scripts expected to run longer than N seconds with no output. Use raw channel with `settimeout(None)` for any setup/export script that could run silently for >30 seconds.

**Affected envs:** Any environment where setup_task.sh or export_result.sh runs a multi-step operation (DB migrations, service restarts, file processing) without producing stdout during execution.

---

## 35. Verify Claims Against the User's Actual Entry Point

When reporting that a feature works "end to end" or has been "visually verified," the verification must use the exact path the user will use — not a parallel test script that bypasses parts of the lifecycle.

**The bug:**
While building `cua_world-macos/google_earth_env`, an end-to-end test script called `runner.exec_capture("open -a 'Google Earth Pro'")` *after* `env.reset()`. That bypassed the task's `pre_task` hook (which killed the app). The script reported "visually verified, screenshots show the app running." When the user ran the actual CLI (`gym-anything run … -i`), they saw an empty desktop — because the CLI honors `pre_task` and pre_task had killed the app. The visual proof was for a code path the user would never run.

**The fix:**
- If the user will run a CLI command, run that exact CLI command (or simulate it faithfully — same reset semantics, same hooks, same flags).
- For GUI/visual claims, capture the screenshot the user's flow produces, not one from a custom script that took a different path.
- If you diverge from the user's path for convenience (skip a slow step, manually launch instead of waiting for the agent), **state it explicitly**: "I tested X by bypassing Y; you'll see Z when running the real flow."
- "It passes the verifier in my probe" ≠ "you'll see the expected state when you run it." Especially for interactive/GUI features, the user's eyes are the verifier.

**Rule:** Before claiming verification, ask "would the user, running their actual command, observe what I'm claiming?" If unsure, run their command.

**Affected scenarios:** Any time an agent reports completion of a feature that has both a programmatic surface (verifier, exec_capture) and a user-facing surface (VNC viewer, interactive panel, screenshot). The two can disagree if your test script takes a shortcut.

---

## 36. Read & Follow Prior Notes Before Designing — Conventions Are Authoritative

This repo's `env_creation_notes/` (general) and `specific_env_notes/<app>/` (per-app) document hard-won conventions. Treat them as authoritative defaults, not background reading. The convention is correct; if you're tempted to deviate, name it explicitly with the rationale, don't silently invent a new pattern.

**The bug:**
When building `cua_world-macos/google_earth_env`, the prior `specific_env_notes/google_earth/{05,07}_*.md` clearly documented the convention: `pre_task` launches Google Earth, agent tasks are operations inside it (`navigate_to_location`, `search_coordinates`, `create_placemark`, `take_screenshot`). I read those notes at the start of the conversation, then invented a `launch_google_earth` agent task whose `pre_task` *killed* the app and required the agent to re-open it. That contradicted the documented convention and broke interactive testing.

**The fix:**
- Before writing env.json or task.json, check `specific_env_notes/<app>/` for the app you're working on.
- Scan the top-level convention files: `01_environment_structure.md`, `06_env_creation_checklist.md`, this file, plus `11_windows_environments.md` (Windows) / `12_macos_environments.md` (macOS) / `android_env_creation_guide.md` (Android).
- For task patterns specifically, the canonical reference is `task_creation_notes/` under `extras/research/task_generation/propose_and_amplify/memory/`.
- **Reading the notes is not enough — cross-check your design against them.** If your task design names a pattern the notes don't mention, that's a smell. Either find why the convention is different (and document the deviation), or change the design.
- If the convention says "agent operates inside the launched app," do not write "launch the app" as an agent task.

**Rule:** Conventions documented in `env_creation_notes/` and `specific_env_notes/` reflect hundreds of hours of experience across 100+ envs. Default to following them. Surprises (deviations) need explicit justification.

**Affected scenarios:** Every new env, every new task. Especially when the app already has prior notes — the notes encode app-specific gotchas (Google Earth dialogs, OpenEMR DB shape, Aerobridge Django patterns) that are not obvious from the source.

---

## 37. Probe Before Speculating — Don't Present Inferences as Fact

When stating something about an external system (API capability, file content, install behavior, etc.), either probe directly or mark the statement as inference. For external services with credentials in scope, the bar to probe is very low: one curl, one SDK call, one file read usually answers the question.

**The bug:**
When analyzing use.computer's caching story, I wrote: *"docs hint at one base per fleet."* That was extrapolation from a single phrase ("cloned from a base image") — presented as fact. The user pushed back: *"what exactly is that?? please confirm exactly what is possible and what is not at this point."* A 30-second probe (`GET /v1/platforms`) revealed there were actually **two** named base images, plus the API would silently accept a third — completely different reality. Speculation cost trust and time; probing would have been faster and right.

**The fix:**
- When making a factual claim about external behavior, probe first. One HTTP call, one SDK invocation, one file read is almost always cheaper than a paragraph of speculation.
- When you must state something without probing, prefix it: "I infer …", "extrapolating from a single mention …", "based on the SDK shape, probably …". This lets the reader weight the claim correctly.
- For environment installs, run the install script against a real sandbox once and inspect the actual error — don't reason about what's likely to happen.
- For repo files, read the file rather than guess from a grep snippet. The Read tool is cheap.
- If the user explicitly authorizes probing (API key, "don't worry about charges"), be more aggressive: spin up a real sandbox, install a real package, exercise a real flow.

**Specific anti-pattern this targets:** the "research summary that sounds confident but is mostly inference" pattern. AGENTS.md is explicit: "Propose the proper integration and execute on it… not options dressed as cowardice." Probe-then-state, not infer-then-state.

**Affected scenarios:** any task that depends on the actual behavior of an external service or unfamiliar code path. Especially when an API key or live system is in reach — speculation in that situation is unforced error.
