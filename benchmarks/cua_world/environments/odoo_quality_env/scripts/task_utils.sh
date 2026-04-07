#!/bin/bash
# Shared utilities for Odoo Quality tasks
# Source this file: source /workspace/scripts/task_utils.sh
# NOTE: Do NOT use set -e before sourcing this file (Pattern #25 in cross_cutting_patterns.md)

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_quality"
ODOO_USER="admin"
ODOO_PASSWORD="admin"
ODOO_DIR="/opt/odoo"
# Required for all xdotool/wmctrl/scrot commands to reach ga's X session
export XAUTHORITY=/run/user/1000/gdm/Xauthority

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

# ---------------------------------------------------------------------------
# Screenshot
# ---------------------------------------------------------------------------
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    # Try scrot first (works without GNOME compositor), then xwd+convert, then import
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    (DISPLAY=:1 xwd -root -silent 2>/dev/null | convert - "$path" 2>/dev/null) || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
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
# ensure_firefox: Launch Firefox if not running, log in, navigate to URL.
#
# Design: post_start does the headless warm-up (creates auto .default*
# profile with user.js). Each pre_task call launches Firefox fresh from
# the savevm snapshot (no prior Firefox state → no snap lock issues).
#
# CRITICAL: Do NOT create custom profiles.ini or use -profile flag with
# snap Firefox — that causes blank rendering (odoo_crm_env lesson).
# Instead, rely on the auto-generated .default* profile created in post_start.
# ---------------------------------------------------------------------------
ensure_firefox() {
    local url="${1:-http://localhost:8069/web/login?db=odoo_quality}"
    local SNAP_FF_MOZILLA="/home/ga/snap/firefox/common/.mozilla/firefox"

    # Kill stale Firefox from checkpoint restore (snap processes become zombies)
    if pgrep -f firefox > /dev/null 2>&1; then
        if ! DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|odoo"; then
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

    # Launch Firefox as ga user — snap Firefox requires user context, not root
    # XAUTHORITY must be set explicitly; /run/user/1000/gdm/Xauthority is the live 102-byte file
    # --new-instance avoids "already running" issues from snapshot restore
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
    DISPLAY=:1 xdotool type --clearmodifiers "http://localhost:8069/web/login?db=odoo_quality"
    DISPLAY=:1 xdotool key Return
    sleep 8

    # Log in to Odoo
    # Coordinates verified interactively for 1920x1080 maximized Firefox with Odoo 17
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

    # Dismiss Firefox "save password" popup (Escape dismisses it without saving)
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
odoo_rpc() {
    # Usage: odoo_rpc <model> <method> <json_args>
    # Returns JSON result
    local model="$1"
    local method="$2"
    local args="${3:-[]}"
    python3 << PYTHON_EOF
import xmlrpc.client, json, sys
url = '$ODOO_URL'
db = '$ODOO_DB'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, '$ODOO_USER', '$ODOO_PASSWORD', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    result = models.execute_kw(db, uid, '$ODOO_PASSWORD', '$model', '$method', $args)
    print(json.dumps(result))
except Exception as e:
    print('[]', file=sys.stdout)
    print(f'Error: {e}', file=sys.stderr)
PYTHON_EOF
}

# Count quality alerts
count_quality_alerts() {
    python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    count = models.execute_kw(db, uid, 'admin', 'quality.alert', 'search_count', [[]])
    print(count)
except Exception as e:
    print(0)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
}

# Count quality control points
count_quality_points() {
    python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    count = models.execute_kw(db, uid, 'admin', 'quality.point', 'search_count', [[]])
    print(count)
except Exception as e:
    print(0)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
}

# Count quality teams
count_quality_teams() {
    python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_quality'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    count = models.execute_kw(db, uid, 'admin', 'quality.alert.team', 'search_count', [[]])
    print(count)
except Exception as e:
    print(0)
    print(f"Error: {e}", file=sys.stderr)
PYTHON_EOF
}

# Record baseline for anti-gaming (count of records before task)
record_task_baseline() {
    local task_name="$1"
    local baseline_file="/tmp/odoo_quality_baseline_${task_name}.json"
    python3 << PYTHON_EOF
import xmlrpc.client, json, time, sys
url = '$ODOO_URL'
db = '$ODOO_DB'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, '$ODOO_USER', '$ODOO_PASSWORD', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    alert_count = models.execute_kw(db, uid, '$ODOO_PASSWORD', 'quality.alert', 'search_count', [[]])
    check_count = models.execute_kw(db, uid, '$ODOO_PASSWORD', 'quality.check', 'search_count', [[]])
    point_count = models.execute_kw(db, uid, '$ODOO_PASSWORD', 'quality.point', 'search_count', [[]])
    team_count = models.execute_kw(db, uid, '$ODOO_PASSWORD', 'quality.alert.team', 'search_count', [[]])

    baseline = {
        'timestamp': time.time(),
        'task': '$task_name',
        'alert_count': alert_count,
        'check_count': check_count,
        'point_count': point_count,
        'team_count': team_count,
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
