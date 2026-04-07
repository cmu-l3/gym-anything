#!/bin/bash
# Shared utilities for Sentrifugo task setup scripts

SENTRIFUGO_URL="http://localhost"
SENTRIFUGO_LOGIN_URL="${SENTRIFUGO_URL}"
SENTRIFUGO_ADMIN_EMAIL="admin@sentrifugo.local"
SENTRIFUGO_ADMIN_PASS="Admin@Sfugo24"
DB_NAME="sentrifugo"
DB_USER="sentrifugo"
DB_PASS="sentrifugo123"
DB_ROOT_PASS="rootpass123"
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
FIREFOX_LOG_FILE="/tmp/firefox_task.log"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export DBUS_SESSION_BUS_ADDRESS

# ============================================================
# Logging
# ============================================================
log() {
    echo "[sentrifugo_task] $*"
}

# ============================================================
# Database helpers
# ============================================================
sentrifugo_db_query() {
    local query="$1"
    docker exec sentrifugo-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -N -e "$query" 2>/dev/null
}

sentrifugo_db_root_query() {
    local query="$1"
    docker exec sentrifugo-db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" \
        -N -e "$query" 2>/dev/null
}

sentrifugo_count() {
    local table="$1"
    local where="${2:-1=1}"
    sentrifugo_db_query "SELECT COUNT(*) FROM ${table} WHERE ${where};" 2>/dev/null | tr -d '[:space:]'
}

get_employee_count() {
    sentrifugo_count "main_users" "isactive=1 AND id>1"
}

employee_exists_by_name() {
    local firstname="$1"
    local lastname="$2"
    local count
    count=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_users WHERE firstname='${firstname}' AND lastname='${lastname}' AND isactive=1;" 2>/dev/null | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

get_employee_user_id() {
    local firstname="$1"
    local lastname="$2"
    sentrifugo_db_query "SELECT id FROM main_users WHERE firstname='${firstname}' AND lastname='${lastname}' AND isactive=1 LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}

get_employee_by_empid() {
    local empid="$1"
    sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${empid}' AND isactive=1 LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}

job_title_exists() {
    local name="$1"
    local count
    count=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='${name}' AND isactive=1;" 2>/dev/null | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

department_exists() {
    local name="$1"
    local count
    count=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_departments WHERE deptname='${name}' AND isactive=1;" 2>/dev/null | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

leave_type_exists() {
    local name="$1"
    local count
    count=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_employeeleavetypes WHERE leavetype='${name}' AND isactive=1;" 2>/dev/null | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

get_department_count() {
    sentrifugo_count "main_departments" "isactive=1"
}

get_job_title_count() {
    sentrifugo_count "main_jobtitles" "isactive=1"
}

get_leave_type_count() {
    sentrifugo_count "main_employeeleavetypes" "isactive=1"
}

get_holiday_count() {
    local year
    year=$(date +%Y)
    sentrifugo_count "main_holidaydates" "isactive=1 AND holidayyear=${year}"
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
# Sentrifugo login automation (1920x1080 coordinates)
# Login page shows username and password fields
# ============================================================
ensure_sentrifugo_logged_in() {
    local target_url="${1:-${SENTRIFUGO_URL}/dashboard}"

    log "Logging in to Sentrifugo and navigating to: $target_url"

    # Stop any running Firefox and clear locks
    stop_firefox
    clear_firefox_profile_locks
    rm -f "$FIREFOX_LOG_FILE" 2>/dev/null || true

    # Launch Firefox at login page
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${SENTRIFUGO_LOGIN_URL}' > '${FIREFOX_LOG_FILE}' 2>&1 &"

    # Wait for window
    local wid=""
    if ! wid=$(wait_for_firefox_main_window 30); then
        log "Firefox did not start; retrying with sudo -u ga..."
        sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${SENTRIFUGO_LOGIN_URL}' > '${FIREFOX_LOG_FILE}' 2>&1 &"
        wid=$(wait_for_firefox_main_window 30) || true
    fi

    if [ -z "$wid" ]; then
        log "ERROR: Firefox failed to start for Sentrifugo login"
        return 1
    fi

    focus_window "$wid" || true
    maximize_active_window
    sleep 6  # Wait for Sentrifugo login page to render

    # Fill login form (username ~(990,584), password ~(990,662) in 1920x1080)
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus --sync "$wid" 2>/dev/null || true
    sleep 0.5

    # Click username field
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove --sync 990 584 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+a 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 50 --clearmodifiers "${SENTRIFUGO_ADMIN_EMAIL}" 2>/dev/null || true
    sleep 0.5

    # Tab to password field and type
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Tab 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 50 --clearmodifiers "${SENTRIFUGO_ADMIN_PASS}" 2>/dev/null || true
    sleep 0.3

    # Submit
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Return 2>/dev/null || true
    sleep 6  # Wait for login to process

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
    sleep 5  # Wait for page to load

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
export -f sentrifugo_db_query
export -f sentrifugo_db_root_query
export -f sentrifugo_count
export -f get_employee_count
export -f employee_exists_by_name
export -f get_employee_user_id
export -f get_employee_by_empid
export -f job_title_exists
export -f department_exists
export -f leave_type_exists
export -f get_department_count
export -f get_job_title_count
export -f get_leave_type_count
export -f get_holiday_count
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
export -f ensure_sentrifugo_logged_in
export -f json_escape
export -f safe_write_result
