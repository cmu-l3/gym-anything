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
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.5
    fi
}

# ---------------------------------------------------------------
# Ensure Firefox is running at OpenClinic GA URL
# ---------------------------------------------------------------
ensure_openclinic_browser() {
    local url="${1:-http://localhost:10088/openclinic}"

    # Check if Firefox is already running
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|localhost"; then
        echo "Firefox already running"
    else
        echo "Starting Firefox..."
        pkill -f firefox 2>/dev/null || true
        sleep 2
        su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox_task.log 2>&1 &"
        sleep 6
    fi

    # Wait for Firefox window
    if ! wait_for_window "firefox\|mozilla\|OpenClinic\|localhost" 30; then
        echo "WARNING: Firefox window not detected"
    fi

    # Maximize and focus
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
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

echo "task_utils.sh loaded (MySQL: $MYSQL_BIN via $MYSQL_SOCKET)"
