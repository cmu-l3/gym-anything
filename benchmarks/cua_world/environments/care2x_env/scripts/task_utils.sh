#!/bin/bash
# Shared utilities for Care2x task setup scripts

CARE2X_URL="http://localhost"
CARE2X_DB="care2x"
CARE2X_DB_USER="care2x"
CARE2X_DB_PASS="care2x_pass"
CARE2X_ADMIN_USER="admin"
CARE2X_ADMIN_PASS="care2x_admin"

# ── Database helpers ──────────────────────────────────────────────────────────

care2x_query() {
    local sql="$1"
    mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "$sql" 2>/dev/null
}

care2x_query_single() {
    local sql="$1"
    mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "$sql" 2>/dev/null | head -1
}

# Get patient PID by name
get_patient_pid() {
    local first="$1"
    local last="$2"
    care2x_query_single "SELECT pid FROM care_person WHERE name_first='$first' AND name_last='$last' LIMIT 1;"
}

# Get patient count
get_patient_count() {
    care2x_query_single "SELECT COUNT(*) FROM care_person;"
}

# ── Service health ────────────────────────────────────────────────────────────

ensure_care2x_running() {
    # Check if Apache is running
    if ! systemctl is-active apache2 >/dev/null 2>&1; then
        echo "Starting Apache..."
        systemctl start apache2
        sleep 3
    fi

    # Check if MariaDB is running
    if ! systemctl is-active mariadb >/dev/null 2>&1; then
        echo "Starting MariaDB..."
        systemctl start mariadb
        sleep 3
    fi

    # Quick HTTP check
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$CARE2X_URL" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
        echo "Care2x already running (HTTP $http_code)"
        return 0
    fi

    echo "Waiting for Care2x..."
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$CARE2X_URL" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
            echo "Care2x ready after ${elapsed}s (HTTP $http_code)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    echo "WARNING: Care2x may not be fully ready"
    return 0
}

# ── Firefox / window helpers ─────────────────────────────────────────────────

wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    echo "Waiting for window: $pattern (${timeout}s max)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "  Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "  WARNING: window '$pattern' not found after ${timeout}s"
    return 1
}

get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1}' | head -1
}

focus_firefox() {
    local WID
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 0.5
    fi
}

ensure_firefox_on_url() {
    local url="${1:-$CARE2X_URL}"

    # Kill any existing firefox for a clean start
    pkill -f firefox 2>/dev/null || true
    sleep 2

    echo "Starting Firefox on $url ..."
    su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox_task.log 2>&1 &"
    sleep 5

    wait_for_window "firefox\|mozilla\|Care2x\|care2x" 30
    focus_firefox
    # Dismiss any Firefox UI dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
}

navigate_to_url() {
    local url="$1"
    echo "Navigating to $url..."
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$url" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 4
    focus_firefox
}

take_screenshot() {
    local outfile="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$outfile" 2>/dev/null || \
    DISPLAY=:1 scrot "$outfile" 2>/dev/null || true
    [ -f "$outfile" ] && echo "Screenshot: $outfile" || echo "WARNING: screenshot failed"
}

# Auto-start services when task_utils.sh is sourced
ensure_care2x_running

# Export all functions
export -f care2x_query care2x_query_single get_patient_pid get_patient_count
export -f ensure_care2x_running
export -f wait_for_window get_firefox_window_id focus_firefox ensure_firefox_on_url navigate_to_url
export -f take_screenshot
