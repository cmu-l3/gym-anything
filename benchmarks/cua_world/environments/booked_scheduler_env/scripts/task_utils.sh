#!/bin/bash
# Shared utilities for Booked Scheduler task setup and export scripts

BOOKED_LOGIN_URL="http://localhost/Web/index.php"
BOOKED_DASHBOARD_URL="http://localhost/Web/dashboard.php"
BOOKED_SCHEDULE_URL="http://localhost/Web/schedule.php"
BOOKED_ADMIN_URL="http://localhost/Web/admin/manage_resources.php"

# ============================================================
# Window management
# ============================================================

wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s" >&2
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout: Window not found after ${timeout}s" >&2
    return 1
}

get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | head -1 | awk '{print $1}'
}

focus_firefox() {
    local WID
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Firefox focused and maximized" >&2
        return 0
    fi
    echo "Firefox window not found" >&2
    return 1
}

# ============================================================
# Firefox management
# ============================================================

restart_firefox() {
    local url="${1:-$BOOKED_LOGIN_URL}"
    echo "Restarting Firefox with URL: $url" >&2

    # Kill existing Firefox
    pkill -9 -f firefox 2>/dev/null || true
    sleep 2

    # Remove lock files
    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true

    # Launch Firefox
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox '$url' > /tmp/firefox_task.log 2>&1 &"

    # Wait for window
    wait_for_window "firefox\|mozilla" 30
    sleep 2
    focus_firefox
}

ensure_firefox_running() {
    local url="${1:-$BOOKED_LOGIN_URL}"
    if ! pgrep -x "firefox" > /dev/null 2>&1; then
        echo "Firefox not running, starting..." >&2
        restart_firefox "$url"
    else
        echo "Firefox already running" >&2
        focus_firefox
    fi
}

# ============================================================
# Database queries
# ============================================================

booked_db_query() {
    local query="$1"
    docker exec booked-db mysql -ubooked_user -ppassword bookedscheduler -N -e "$query" 2>/dev/null
}

booked_db_query_verbose() {
    local query="$1"
    docker exec booked-db mysql -ubooked_user -ppassword bookedscheduler -e "$query" 2>/dev/null
}

get_resource_count() {
    booked_db_query "SELECT COUNT(*) FROM resources"
}

get_reservation_count() {
    booked_db_query "SELECT COUNT(*) FROM reservation_instances"
}

get_user_count() {
    booked_db_query "SELECT COUNT(*) FROM users"
}

resource_exists() {
    local name="$1"
    local count
    count=$(booked_db_query "SELECT COUNT(*) FROM resources WHERE LOWER(TRIM(name)) = LOWER(TRIM('$name'))")
    [ "$count" -gt 0 ] 2>/dev/null
}

# ============================================================
# Service health
# ============================================================

wait_for_http() {
    local url="$1"
    local timeout_sec="${2:-120}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout_sec" ]; do
        local code
        code=$(curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
        if [ "$code" = "200" ] || [ "$code" = "302" ]; then
            echo "Service ready at $url after ${elapsed}s" >&2
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "Timeout waiting for $url after ${timeout_sec}s" >&2
    return 1
}

wait_for_booked() {
    echo "Checking Booked Scheduler service..." >&2
    wait_for_http "http://localhost/Web/index.php" 120
}

# ============================================================
# Screenshots
# ============================================================

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot" >&2
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file" >&2
}

# ============================================================
# Safe file writing
# ============================================================

safe_write_result() {
    local content="$1"
    local path="$2"
    local TEMP
    TEMP=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$TEMP"
    rm -f "$path" 2>/dev/null || sudo rm -f "$path" 2>/dev/null || true
    cp "$TEMP" "$path" 2>/dev/null || sudo cp "$TEMP" "$path"
    chmod 666 "$path" 2>/dev/null || sudo chmod 666 "$path" 2>/dev/null || true
    rm -f "$TEMP"
}

# ============================================================
# Export functions
# ============================================================

export -f wait_for_window get_firefox_window_id focus_firefox
export -f restart_firefox ensure_firefox_running
export -f booked_db_query booked_db_query_verbose
export -f get_resource_count get_reservation_count get_user_count resource_exists
export -f wait_for_http wait_for_booked
export -f take_screenshot safe_write_result
