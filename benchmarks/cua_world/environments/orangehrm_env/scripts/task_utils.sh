#!/bin/bash
# Shared utilities for OrangeHRM task setup scripts

ORANGEHRM_URL="http://localhost:8000"
ORANGEHRM_LOGIN_URL="${ORANGEHRM_URL}/web/index.php/auth/login"
ORANGEHRM_ADMIN_USER="admin"
ORANGEHRM_ADMIN_PASS="Admin@OHrm2024!"
DB_NAME="orangehrm"
DB_USER="orangeuser"
DB_PASS="orangepass123"
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
FIREFOX_LOG_FILE="/tmp/firefox_task.log"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export DBUS_SESSION_BUS_ADDRESS

# ============================================================
# Logging
# ============================================================
log() {
    echo "[orangehrm_task] $*"
}

# ============================================================
# Database helpers
# ============================================================
orangehrm_db_query() {
    local query="$1"
    docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -N -e "$query" 2>/dev/null
}

orangehrm_count() {
    local table="$1"
    local where="${2:-1=1}"
    orangehrm_db_query "SELECT COUNT(*) FROM ${table} WHERE ${where};" 2>/dev/null | tr -d '[:space:]'
}

get_employee_count() {
    orangehrm_count "hs_hr_employee" "purged_at IS NULL"
}

employee_exists_by_name() {
    local firstname="$1"
    local lastname="$2"
    local count
    count=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE emp_firstname='${firstname}' AND emp_lastname='${lastname}' AND purged_at IS NULL;" 2>/dev/null | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

get_employee_empnum() {
    local firstname="$1"
    local lastname="$2"
    orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='${firstname}' AND emp_lastname='${lastname}' AND purged_at IS NULL LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}

job_title_exists() {
    local name="$1"
    local count
    count=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_job_title WHERE job_title='${name}' AND is_deleted=0;" 2>/dev/null | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

leave_type_exists() {
    local name="$1"
    local count
    count=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_leave_type WHERE name='${name}' AND deleted=0;" 2>/dev/null | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

get_leave_type_count() {
    orangehrm_count "ohrm_leave_type" "deleted=0"
}

get_job_title_count() {
    orangehrm_count "ohrm_job_title" "is_deleted=0"
}

# ============================================================
# HTTP helpers
# ============================================================
wait_for_http() {
    local url="$1"
    local timeout_sec="${2:-120}"
    local elapsed=0

    log "Waiting for HTTP readiness: $url"
    while [ "$elapsed" -lt "$timeout_sec" ]; do
        local code
        code=$(curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
            log "HTTP ready after ${elapsed}s (HTTP $code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    log "ERROR: Timeout waiting for HTTP at $url"
    return 1
}

# ============================================================
# Window management
# ============================================================
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    return 1
}

get_firefox_window_id() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null \
        | grep -i 'firefox\|mozilla' | grep -vi 'close firefox' | awk '{print $1; exit}'
}

focus_window() {
    local wid="$1"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$wid" 2>/dev/null || \
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "$wid" 2>/dev/null || return 1
    sleep 0.3
}

maximize_active_window() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

focus_firefox() {
    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        maximize_active_window
        return 0
    fi
    return 1
}

# ============================================================
# Screenshot
# ============================================================
take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$output" 2>/dev/null || \
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$output" 2>/dev/null || true
}

# ============================================================
# Firefox lifecycle
# ============================================================
stop_firefox() {
    pkill -TERM -f firefox 2>/dev/null || true
    for _ in $(seq 1 40); do
        if ! pgrep -f firefox >/dev/null 2>&1; then break; fi
        sleep 0.5
    done
    if pgrep -f firefox >/dev/null 2>&1; then
        pkill -KILL -f firefox 2>/dev/null || true
        sleep 1
    fi
}

clear_firefox_profile_locks() {
    for pdir in \
        "$FIREFOX_PROFILE_DIR" \
        "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile"; do
        rm -f \
            "$pdir/lock" \
            "$pdir/.parentlock" \
            "$pdir/parent.lock" \
            "$pdir/singletonLock" \
            "$pdir/singletonCookie" \
            "$pdir/singletonSocket" \
            "$pdir/sessionstore.jsonlz4" \
            2>/dev/null || true
        rm -rf "$pdir/sessionstore-backups" 2>/dev/null || true
    done
}

has_close_firefox_dialog() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "Close Firefox"
}

dismiss_close_firefox_dialog() {
    local wid
    wid=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null \
        | grep -i "Close Firefox" | awk '{print $1; exit}')
    if [ -n "$wid" ]; then
        log "Dismissing 'Close Firefox' dialog..."
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
        sleep 1
    fi
}

wait_for_firefox_main_window() {
    local timeout_sec="${1:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout_sec" ]; do
        if has_close_firefox_dialog; then
            dismiss_close_firefox_dialog
            sleep 1
        else
            local wid
            wid=$(get_firefox_window_id)
            if [ -n "$wid" ]; then
                echo "$wid"
                return 0
            fi
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    return 1
}

navigate_to_url() {
    local url="$1"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 15 --clearmodifiers "$url" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Return 2>/dev/null || true
}

restart_firefox() {
    local url="$1"
    local attempts="${2:-3}"

    dismiss_close_firefox_dialog

    for attempt in $(seq 1 "$attempts"); do
        log "Starting Firefox (attempt ${attempt}/${attempts}): $url"
        stop_firefox
        dismiss_close_firefox_dialog
        clear_firefox_profile_locks
        rm -f "$FIREFOX_LOG_FILE" 2>/dev/null || true

        sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '$url' > '$FIREFOX_LOG_FILE' 2>&1 &"

        local wid=""
        if wid=$(wait_for_firefox_main_window 30); then
            focus_window "$wid" || true
            maximize_active_window
            navigate_to_url "$url"
            return 0
        fi
        log "Firefox did not start cleanly on attempt ${attempt}."
        tail -n 20 "$FIREFOX_LOG_FILE" 2>/dev/null || true
        sleep 2
    done

    log "ERROR: Failed to start Firefox after ${attempts} attempts."
    return 1
}

# ============================================================
# OrangeHRM login automation (1920x1080 coordinates)
# Login page: /web/index.php/auth/login
# Username field is the first input, password second
# ============================================================
ensure_orangehrm_logged_in() {
    local target_url="${1:-${ORANGEHRM_URL}/web/index.php/dashboard/index}"

    log "Logging in to OrangeHRM and navigating to: $target_url"

    # Stop any running Firefox and clear locks
    stop_firefox
    clear_firefox_profile_locks
    rm -f "$FIREFOX_LOG_FILE" 2>/dev/null || true

    # Launch Firefox at login page
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${ORANGEHRM_LOGIN_URL}' > '${FIREFOX_LOG_FILE}' 2>&1 &"

    # Wait for window
    local wid=""
    if ! wid=$(wait_for_firefox_main_window 30); then
        log "Firefox did not start; retrying with sudo -u ga..."
        sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${ORANGEHRM_LOGIN_URL}' > '${FIREFOX_LOG_FILE}' 2>&1 &"
        wid=$(wait_for_firefox_main_window 30) || true
    fi

    if [ -z "$wid" ]; then
        log "ERROR: Firefox failed to start for OrangeHRM login"
        return 1
    fi

    focus_window "$wid" || true
    maximize_active_window
    sleep 6  # Wait for OrangeHRM login page to render (JS-heavy SPA)

    # Fill login form
    # OrangeHRM 5.x login page: username at ~(813,596), password at ~(813,683) in 1920x1080
    # (VG 1280x720 scale: username at (542,397), password at (542,455))
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus --sync "$wid" 2>/dev/null || true
    sleep 0.5

    # Click username field
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove --sync 813 596 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+a 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 50 --clearmodifiers "${ORANGEHRM_ADMIN_USER}" 2>/dev/null || true
    sleep 0.3

    # Click password field
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove --sync 813 683 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 50 --clearmodifiers "${ORANGEHRM_ADMIN_PASS}" 2>/dev/null || true
    sleep 0.3

    # Submit
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Return 2>/dev/null || true
    sleep 6  # Wait for SPA navigation after login

    log "Login submitted, navigating to: $target_url"

    # Navigate to target URL
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus --sync "$wid" 2>/dev/null || true
        sleep 0.3
    fi
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+a 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 20 --clearmodifiers "$target_url" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Return 2>/dev/null || true
    sleep 6  # Wait for SPA to load the page

    log "Navigated to $target_url"
    return 0
}

# ============================================================
# JSON helpers
# ============================================================
json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

safe_write_result() {
    local json="$1"
    local path="${2:-/tmp/task_result.json}"
    local tmp
    tmp=$(mktemp /tmp/task_result.XXXXXX.json)
    printf '%s\n' "$json" > "$tmp"
    rm -f "$path" 2>/dev/null || sudo rm -f "$path" 2>/dev/null || true
    cp "$tmp" "$path" 2>/dev/null || sudo cp "$tmp" "$path"
    chmod 666 "$path" 2>/dev/null || sudo chmod 666 "$path" 2>/dev/null || true
    rm -f "$tmp"
}

# Export all functions
export -f log
export -f orangehrm_db_query
export -f orangehrm_count
export -f get_employee_count
export -f employee_exists_by_name
export -f get_employee_empnum
export -f job_title_exists
export -f leave_type_exists
export -f get_leave_type_count
export -f get_job_title_count
export -f wait_for_http
export -f wait_for_window
export -f get_firefox_window_id
export -f focus_window
export -f maximize_active_window
export -f focus_firefox
export -f take_screenshot
export -f stop_firefox
export -f clear_firefox_profile_locks
export -f has_close_firefox_dialog
export -f dismiss_close_firefox_dialog
export -f wait_for_firefox_main_window
export -f navigate_to_url
export -f restart_firefox
export -f ensure_orangehrm_logged_in
export -f json_escape
export -f safe_write_result
