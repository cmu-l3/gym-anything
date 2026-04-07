#!/bin/bash
# task_utils.sh - Shared utilities for OpenClinic GA tasks
# Source this file in setup_task.sh scripts
#
# OpenClinic GA MySQL details:
#   Binary: /opt/openclinic/mysql5/bin/mysql
#   Socket: /tmp/mysql5.sock
#   User: root (no password)
#   Databases: ocadmin_dbo (patients), openclinic_dbo (clinical data)

MYSQL_BIN="/opt/openclinic/mysql5/bin/mysql"
MYSQL_SOCKET="/tmp/mysql5.sock"
MYSQL_OPTS="-S $MYSQL_SOCKET -u root"

# ---------------------------------------------------------------
# MySQL helpers
# ---------------------------------------------------------------
# Query ocadmin_dbo (patient demographics)
admin_query() {
    local query="$1"
    $MYSQL_BIN $MYSQL_OPTS ocadmin_dbo -N -e "$query" 2>/dev/null
}

# Query openclinic_dbo (clinical data)
clinical_query() {
    local query="$1"
    $MYSQL_BIN $MYSQL_OPTS openclinic_dbo -N -e "$query" 2>/dev/null
}

# Generic query (specify db as first arg)
db_query() {
    local db="$1"
    local query="$2"
    $MYSQL_BIN $MYSQL_OPTS "$db" -N -e "$query" 2>/dev/null
}

# ---------------------------------------------------------------
# Screenshot
# ---------------------------------------------------------------
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ---------------------------------------------------------------
# Wait for a window with a matching title pattern
# ---------------------------------------------------------------
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# ---------------------------------------------------------------
# Get Firefox window ID
# ---------------------------------------------------------------
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|openclinic\|localhost" | head -1 | awk '{print $1}'
}

# ---------------------------------------------------------------
# Focus a window by ID
# ---------------------------------------------------------------
focus_window() {
    local wid="$1"
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -k off 2>/dev/null || true
        DISPLAY=:1 wmctrl -s 0 2>/dev/null || true
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 xdotool windowactivate --sync "$wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 0.5
    fi
}

# ---------------------------------------------------------------
# Clear Firefox crash/session restore state
# ---------------------------------------------------------------
clear_firefox_session_state() {
    local bases=(
        "/home/ga/snap/firefox/common/.mozilla/firefox"
        "/home/ga/.mozilla/firefox"
    )
    local base
    for base in "${bases[@]}"; do
        [ -d "$base" ] || continue
        find "$base" -maxdepth 2 \( -name "sessionstore.jsonlz4" -o -name "sessionCheckpoints.json" -o -name "recovery.jsonlz4" -o -name "previous.jsonlz4" \) -type f -delete 2>/dev/null || true
        find "$base" -maxdepth 2 -name "sessionstore-backups" -type d -exec rm -rf {} + 2>/dev/null || true
    done
}

# ---------------------------------------------------------------
# Ensure Firefox is running at OpenClinic GA URL
# ---------------------------------------------------------------
ensure_openclinic_browser() {
    local url="${1:-http://localhost:10088/openclinic}"

    echo "Launching fresh Firefox session..."
    pkill -f firefox 2>/dev/null || true
    sleep 2
    pkill -9 -f firefox 2>/dev/null || true
    clear_firefox_session_state
    su - ga -c "DISPLAY=:1 firefox --new-window '$url' > /tmp/firefox_task.log 2>&1 &"
    sleep 6

    # Wait for Firefox window
    if ! wait_for_window "firefox\|mozilla\|OpenClinic\|localhost" 30; then
        echo "WARNING: Firefox window not detected"
    fi

    # Maximize and focus
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        sleep 1
    fi

    # Dismiss any Firefox dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
}

# ---------------------------------------------------------------
# Navigate Firefox to a specific URL
# ---------------------------------------------------------------
navigate_to_url() {
    local url="$1"
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 3
}

# ---------------------------------------------------------------
# Record task start timestamp (anti-gaming)
# ---------------------------------------------------------------
record_task_start() {
    local timestamp_file="${1:-/tmp/task_start_timestamp}"
    date +%s > "$timestamp_file"
    echo "Task start timestamp: $(cat $timestamp_file) ($(date))"
}

# ---------------------------------------------------------------
# Get patient count from AdminView
# ---------------------------------------------------------------
get_patient_count() {
    admin_query "SELECT COUNT(*) FROM adminview" 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------
# Ensure OpenClinic GA services are running
# This is critical when loading from a QEMU checkpoint — services
# that were running during checkpoint creation are NOT running
# when the checkpoint is restored.
# ---------------------------------------------------------------
ensure_openclinic_running() {
    local OPENCLINIC_ROOT="/opt/openclinic"
    local OPENCLINIC_URL="http://localhost:10088/openclinic"

    # Quick check: is it already responding?
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$OPENCLINIC_URL" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        echo "OpenClinic GA already running (HTTP $http_code)"
        return 0
    fi

    echo "OpenClinic GA not responding (HTTP $http_code). Starting services..."

    # Clean up stale PID files and sockets
    pkill -f "catalina" 2>/dev/null || true
    pkill -f "mysqld.*openclinic" 2>/dev/null || true
    sleep 2
    pkill -9 -f "catalina" 2>/dev/null || true
    pkill -9 -f "mysqld.*openclinic" 2>/dev/null || true
    sleep 1
    find "$OPENCLINIC_ROOT" -name "*.pid" -delete 2>/dev/null || true
    rm -f "$MYSQL_SOCKET" 2>/dev/null || true
    rm -f "$OPENCLINIC_ROOT/tomcat8/bin/catalina.pid" 2>/dev/null || true

    # Start services
    if [ -x "$OPENCLINIC_ROOT/restart_openclinic" ]; then
        "$OPENCLINIC_ROOT/restart_openclinic" 2>/dev/null || true
    elif [ -x "$OPENCLINIC_ROOT/start_openclinic" ]; then
        "$OPENCLINIC_ROOT/start_openclinic" 2>/dev/null || true
    else
        echo "ERROR: No OpenClinic start script found"
        return 1
    fi

    # Poll for HTTP readiness (up to 120s)
    local timeout=120
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$OPENCLINIC_URL" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
            echo "OpenClinic GA is ready after ${elapsed}s (HTTP $http_code)"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting for OpenClinic... ${elapsed}s (HTTP $http_code)"
        fi
    done

    if [ "$elapsed" -ge "$timeout" ]; then
        echo "WARNING: OpenClinic may not be ready after ${timeout}s"
    fi

    # Poll for MySQL readiness (up to 60s)
    local mysql_attempts=0
    while [ "$mysql_attempts" -lt 20 ]; do
        if $MYSQL_BIN -S "$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then
            echo "MySQL is accessible (attempt $((mysql_attempts+1)))"
            return 0
        fi
        sleep 3
        mysql_attempts=$((mysql_attempts + 1))
    done

    echo "WARNING: MySQL may not be accessible"
    return 0
}

# Auto-start services when task_utils.sh is sourced
ensure_openclinic_running

echo "task_utils.sh loaded (MySQL: $MYSQL_BIN via $MYSQL_SOCKET)"
