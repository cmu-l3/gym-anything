#!/bin/bash
# Shared utilities for Odoo HR tasks
# Source this file: source /workspace/scripts/task_utils.sh
# NOTE: Do NOT use set -e before sourcing this file (Pattern #25 in cross_cutting_patterns.md)

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_hr"
ODOO_USER="admin"
ODOO_PASSWORD="admin"
ODOO_DIR="/opt/odoo"
# Required for all xdotool/wmctrl/scrot commands to reach ga's X session
export XAUTHORITY=/run/user/1000/gdm/Xauthority

# ---------------------------------------------------------------------------
# Ensure Docker and Odoo containers are running
# This is CRITICAL after VM checkpoint/restore — Docker containers may not
# survive savevm/loadvm and need to be restarted.
# ---------------------------------------------------------------------------
ensure_odoo_running() {
    echo "ensure_odoo_running: checking Docker and Odoo services..."

    # 1. Ensure Docker daemon is running
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        echo "  Docker not running — starting..."
        systemctl start docker
        sleep 5
    fi

    # 2. Check if containers exist and are running
    local web_running db_running
    web_running=$(docker inspect -f '{{.State.Running}}' odoo-web 2>/dev/null || echo "false")
    db_running=$(docker inspect -f '{{.State.Running}}' odoo-db 2>/dev/null || echo "false")

    if [ "$db_running" != "true" ] || [ "$web_running" != "true" ]; then
        echo "  Containers not running (db=$db_running, web=$web_running) — starting..."
        cd "$ODOO_DIR"
        docker compose up -d 2>&1 | tail -5
        sleep 10
    fi

    # 3. Wait for Odoo web to be healthy
    local timeout=120
    local elapsed=0
    echo "  Waiting for Odoo web service..."
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

    echo "  WARNING: Odoo not ready after ${timeout}s — trying docker compose restart..."
    cd "$ODOO_DIR"
    docker compose restart 2>&1 | tail -5
    sleep 15

    # Final check
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$ODOO_URL/web/health" 2>/dev/null || echo "0")
    if [ "$http_code" = "200" ]; then
        echo "  Odoo web ready after restart"
        return 0
    fi

    echo "  ERROR: Odoo still not ready (HTTP $http_code)"
    docker compose logs --tail=20 2>&1 || true
    return 1
}

# ---------------------------------------------------------------------------
# Screenshot
# ---------------------------------------------------------------------------
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    # Remove existing file so ga user can write to /tmp even if owned by root
    rm -f "$path" 2>/dev/null || true
    # Run scrot as ga user who owns the X session (root cannot access GNOME compositor)
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$path'" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || \
    (DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xwd -root -silent 2>/dev/null | convert - "$path" 2>/dev/null) || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$path" 2>/dev/null || true
    echo "Screenshot saved to: $path"
}

# ---------------------------------------------------------------------------
# Firefox navigation
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# ensure_firefox: Ensure Odoo is running, launch Firefox if not running,
# log in, navigate to URL.
#
# Uses snap Firefox auto-generated .default* profile created in post_start.
# Each pre_task hook calls this to bring Firefox to the correct Odoo page.
# ---------------------------------------------------------------------------
ensure_firefox() {
    local url="${1:-http://localhost:8069/web/login?db=odoo_hr}"
    local SNAP_FF_MOZILLA="/home/ga/snap/firefox/common/.mozilla/firefox"

    # *** CRITICAL: Ensure Odoo Docker services are running ***
    # After VM checkpoint/restore, Docker containers may not survive
    ensure_odoo_running

    # Always kill stale Firefox from previous session/restore and start fresh.
    # Snap Firefox survives VM checkpoint poorly — stale processes cause lock dialogs.
    if pgrep -f firefox > /dev/null 2>&1; then
        echo "ensure_firefox: killing existing Firefox (stale after restore)..."
        pkill -f firefox 2>/dev/null || true
        sleep 3
        pkill -9 -f firefox 2>/dev/null || true
        sleep 5
    fi

    # Remove stale profile locks from snapshot restore or previous session
    find "$SNAP_FF_MOZILLA" -name "lock" -delete 2>/dev/null || true
    find "$SNAP_FF_MOZILLA" -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true

    # Clear session restore files to avoid "Restore previous session?" dialog
    for profile_dir in "$SNAP_FF_MOZILLA"/*.default* "$SNAP_FF_MOZILLA"/*.default; do
        if [ -d "$profile_dir" ]; then
            rm -f "$profile_dir"/sessionstore*.jsonlz4 \
                  "$profile_dir/sessionCheckpoints.json" 2>/dev/null || true
            rm -rf "$profile_dir/sessionstore-backups" 2>/dev/null || true
        fi
    done

    # Ensure user.js exists in the snap profile to suppress first-run dialogs
    local profile_dir
    profile_dir=$(find "$SNAP_FF_MOZILLA" -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
    if [ -z "$profile_dir" ]; then
        profile_dir=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
    fi
    if [ -n "$profile_dir" ] && [ ! -f "$profile_dir/user.js" ]; then
        echo "ensure_firefox: writing user.js to suppress first-run dialogs..."
        cat > "$profile_dir/user.js" << 'USERJS_EOF'
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
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
USERJS_EOF
        chown ga:ga "$profile_dir/user.js"
    fi

    # Launch Firefox as ga user
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance about:blank > /dev/null 2>&1 &"
    sleep 14

    # Handle snap lock dialog (defensive)
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "Close Firefox\|Firefox.*lock\|already.*running"; then
        echo "ensure_firefox: lock dialog detected — clearing and retrying..."
        pkill -9 -f firefox 2>/dev/null || true
        sleep 5
        find "$SNAP_FF_MOZILLA" -name "lock" -delete 2>/dev/null || true
        find "$SNAP_FF_MOZILLA" -name ".parentlock" -delete 2>/dev/null || true
        su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance about:blank > /dev/null 2>&1 &"
        sleep 15
    fi

    # Maximize and focus Firefox window
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1

    # Navigate to Odoo login page with explicit DB parameter
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8069/web/login?db=odoo_hr"
    DISPLAY=:1 xdotool key Return
    sleep 8

    # Log in to Odoo
    # Coordinates verified from odoo_quality_env interactive testing at 1920x1080
    # email input: (664,232) in 1280x720 → (994,348) at 1920x1080
    DISPLAY=:1 xdotool mousemove 994 348 click 1
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    DISPLAY=:1 xdotool key Return
    sleep 10

    # Dismiss Firefox "save password" popup
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5

    # Navigate to target URL
    navigate_firefox "$url"

    # Final maximize
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

# ---------------------------------------------------------------------------
# Odoo XML-RPC helpers
# ---------------------------------------------------------------------------
odoo_search_count() {
    local model="$1"
    local domain="${2:-[]}"
    python3 << PYTHON_EOF
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_hr'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    count = models.execute_kw(db, uid, 'admin', '$model', 'search_count', [$domain])
    print(count)
except Exception as e:
    print(0)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
}

# ---------------------------------------------------------------------------
# AUTO-RUN: Ensure Odoo is running when this file is sourced.
# This MUST happen before any task setup script tries XML-RPC calls,
# otherwise set -e + sys.exit(1) will kill the script before ensure_firefox.
# ---------------------------------------------------------------------------
ensure_odoo_running
