#!/bin/bash
# Shared utilities for Odoo scheduling tasks
# Source this file with: source /workspace/scripts/task_utils.sh
# NOTE: Do NOT use set -e before sourcing this file (Pattern #25)

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_scheduling"
ODOO_USER="admin"
ODOO_PASSWORD="admin"
ODOO_DIR="/opt/odoo"

# ---------------------------------------------------------------------------
# Ensure Docker and Odoo containers are running.
# CRITICAL after VM checkpoint/restore — containers may not survive savevm/loadvm.
# ---------------------------------------------------------------------------
ensure_odoo_running() {
    echo "ensure_odoo_running: checking Docker and Odoo services..."
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        echo "  Docker not running — starting..."
        systemctl start docker
        sleep 5
    fi
    local web_running db_running
    web_running=$(docker inspect -f '{{.State.Running}}' odoo-web 2>/dev/null || echo "false")
    db_running=$(docker inspect -f '{{.State.Running}}' odoo-db 2>/dev/null || echo "false")
    if [ "$db_running" != "true" ] || [ "$web_running" != "true" ]; then
        echo "  Containers not running (db=$db_running, web=$web_running) — starting..."
        cd "$ODOO_DIR"
        docker compose up -d 2>&1 | tail -5
        sleep 10
    fi
    local timeout=120 elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/health" 2>/dev/null || echo "0")
        if [ "$http_code" = "200" ]; then
            echo "  Odoo web ready (HTTP 200) after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "  WARNING: Odoo not ready after ${timeout}s — restarting..."
    cd "$ODOO_DIR" && docker compose restart 2>&1 | tail -5
    sleep 15
    return 0
}

# Take a screenshot of the current desktop
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    echo "Screenshot saved to: $path"
}

# Navigate Firefox to a URL
navigate_firefox() {
    local url="$1"
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$url"
    DISPLAY=:1 xdotool key Return
    sleep 3
}

# Ensure Firefox is running with Odoo Calendar visible.
# Design: post_start does NOT launch Firefox, so the savevm snapshot has no
# prior Firefox state. Each pre_task call here is the FIRST-EVER Firefox launch
# in the VM → no snap lock → starts cleanly.
#
# Root cause note: passing -profile /home/ga/.mozilla/firefox/odoo.profile to
# snap Firefox triggers the "Close Firefox" dialog even after lock removal.
# Fix: launch WITHOUT -profile; snap Firefox reads its own profiles.ini which
# already points to odoo.profile as the default profile.
#
# If Firefox is already running (sequential task runs without reset):
#   → just navigate to the target URL
# If Firefox is not running:
#   1. Ensure snap profiles.ini points to odoo.profile
#   2. Remove any stale profile locks
#   3. Launch Firefox (no -profile flag)
#   4. If "Close Firefox" dialog appears: kill, cleanup, retry
#   5. Log in to Odoo (autofocus on username field)
#   6. Navigate to target URL
ensure_firefox() {
    local url="${1:-http://localhost:8069/web#action=calendar.action_calendar_event}"
    local SNAP_FF_MOZILLA="/home/ga/snap/firefox/common/.mozilla/firefox"

    # Kill stale Firefox from checkpoint restore (snap processes become zombies)
    if pgrep -f firefox > /dev/null 2>&1; then
        if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|odoo"; then
            echo "ensure_firefox: killing stale Firefox process..."
            pkill -f firefox 2>/dev/null || true
            sleep 3
            pkill -9 -f firefox 2>/dev/null || true
            sleep 5
        else
            # Firefox running with a window — just navigate
            navigate_firefox "$url"
            DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
            DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
            sleep 1
            return
        fi
    fi

    # Ensure snap Firefox profile directory is configured (handles both fresh
    # installs where snap dirs may not exist and existing checkpoints)
    mkdir -p "$SNAP_FF_MOZILLA/odoo.profile" 2>/dev/null || true
    cat > "$SNAP_FF_MOZILLA/profiles.ini" << 'PROFILES_EOF'
[Profile0]
Name=odoo
IsRelative=1
Path=odoo.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES_EOF
    local SNAP_FF_PROFILE="$SNAP_FF_MOZILLA/odoo.profile"

    # Write user.js preferences to suppress dialogs (session restore, updates, etc.)
    # startup.page=0 → blank page on startup (prevents session restore from SIGKILL crash)
    cat > "$SNAP_FF_PROFILE/user.js" << 'USERJS_EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.startup.page", 0);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
user_pref("app.update.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
USERJS_EOF

    # Clear ALL session store files (prevents session restore after SIGKILL crash).
    # Delete ALL files in sessionstore-backups (not just .jsonlz4 — .baklz4 also triggers restore).
    rm -f "$SNAP_FF_PROFILE"/sessionstore*.jsonlz4 \
          "$SNAP_FF_PROFILE"/.crash-report.ini \
          "$SNAP_FF_PROFILE/sessionCheckpoints.json" 2>/dev/null || true
    rm -rf "$SNAP_FF_PROFILE/sessionstore-backups" 2>/dev/null || true
    mkdir -p "$SNAP_FF_PROFILE/sessionstore-backups" 2>/dev/null || true

    # Remove stale profile locks from all possible locations
    find "$SNAP_FF_MOZILLA" -name "lock" -delete 2>/dev/null || true
    find "$SNAP_FF_MOZILLA" -name ".parentlock" -delete 2>/dev/null || true
    rm -f /home/ga/.mozilla/firefox/odoo.profile/lock \
          /home/ga/.mozilla/firefox/odoo.profile/.parentlock 2>/dev/null || true

    # Launch Firefox WITHOUT -profile (snap reads profiles.ini → odoo.profile).
    # Run directly as current user (ga) — no su needed since hooks run as ga.
    DISPLAY=:1 setsid firefox 'about:blank' &
    sleep 12

    # Handle snap lock dialog (defensive: should not occur with the above fix)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Close Firefox"; then
        echo "ensure_firefox: snap lock dialog detected — clearing and retrying..."
        pkill -9 -f firefox 2>/dev/null || true
        sleep 5
        find "$SNAP_FF_MOZILLA" -name "lock" -delete 2>/dev/null || true
        find "$SNAP_FF_MOZILLA" -name ".parentlock" -delete 2>/dev/null || true
        DISPLAY=:1 setsid firefox 'about:blank' &
        sleep 15
    fi

    # Maximize and focus Firefox window
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1

    # Navigate to Odoo login page
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers 'http://localhost:8069/web/login?db=odoo_scheduling'
    DISPLAY=:1 xdotool key Return
    sleep 8

    # Log in to Odoo — click the email input field directly (more reliable than
    # relying on autofocus which may not fire after programmatic URL bar navigation).
    # Coordinates are for a maximized 1920x1080 Firefox window showing Odoo 17 login.
    DISPLAY=:1 xdotool mousemove 996 350 click 1
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    DISPLAY=:1 xdotool key Return
    sleep 10

    # Navigate to the task's target URL
    navigate_firefox "$url"

    # Final maximize
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

# Ensure the Odoo browser session is logged in (handles session expiry)
ensure_odoo_logged_in() {
    # Navigate to login page and fill credentials
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.3
    DISPLAY=:1 xdotool type "http://localhost:8069/web/login?db=odoo_scheduling"
    DISPLAY=:1 xdotool key Return
    sleep 4
    # Fill in credentials
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type "admin"
    DISPLAY=:1 xdotool key Tab
    sleep 0.2
    DISPLAY=:1 xdotool type "admin"
    DISPLAY=:1 xdotool key Return
    sleep 4
}

# Query Odoo via XML-RPC and return JSON result
# Usage: odoo_search "model.name" "[[['field', '=', 'value']]]" "['field1', 'field2']"
odoo_search() {
    local model="$1"
    local domain="${2:-[[]]}"
    local fields="${3:-['id', 'name']}"
    python3 << PYTHON_EOF
import xmlrpc.client, json, sys
url = '$ODOO_URL'
db = '$ODOO_DB'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, '$ODOO_USER', '$ODOO_PASSWORD', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    results = models.execute_kw(db, uid, '$ODOO_PASSWORD', '$model', 'search_read',
                                [$domain], {'fields': $fields, 'limit': 100})
    print(json.dumps(results))
except Exception as e:
    print(f"[]", file=sys.stdout)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
}

# Get a partner ID by name
# Usage: get_partner_id "Alice Johnson"
get_partner_id() {
    local name="$1"
    python3 << PYTHON_EOF
import xmlrpc.client, sys
url = '$ODOO_URL'
db = '$ODOO_DB'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, '$ODOO_USER', '$ODOO_PASSWORD', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    ids = models.execute_kw(db, uid, '$ODOO_PASSWORD', 'res.partner', 'search',
                            [[['name', '=', '$name']]])
    print(ids[0] if ids else '')
except Exception as e:
    print('', file=sys.stdout)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
}

# Count calendar events (meetings) in the database
count_calendar_events() {
    python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    count = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_count', [[]])
    print(count)
except Exception as e:
    print(0)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
}

# Record the current state for anti-gaming verification
record_task_baseline() {
    local task_name="$1"
    local baseline_file="/tmp/odoo_task_baseline_${task_name}.json"
    python3 << PYTHON_EOF
import xmlrpc.client, json, time, sys
url = '$ODOO_URL'
db = '$ODOO_DB'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, '$ODOO_USER', '$ODOO_PASSWORD', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    event_count = models.execute_kw(db, uid, '$ODOO_PASSWORD', 'calendar.event', 'search_count', [[]])

    baseline = {
        'timestamp': time.time(),
        'task': '$task_name',
        'calendar_event_count': event_count,
    }
    with open('$baseline_file', 'w') as f:
        json.dump(baseline, f)
    print(f"Baseline recorded: {baseline}")
except Exception as e:
    print(f"Warning: Could not record baseline: {e}", file=sys.stderr)
PYTHON_EOF
}

# ---------------------------------------------------------------------------
# AUTO-RUN: Ensure Odoo is running when this file is sourced.
# Must happen before any task setup script tries XML-RPC calls.
# ---------------------------------------------------------------------------
ensure_odoo_running
