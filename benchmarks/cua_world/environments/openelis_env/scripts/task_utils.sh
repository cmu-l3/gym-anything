#!/bin/bash
# Shared task setup utilities for OpenELIS tasks.
# Note: No set -euo pipefail here — this file is sourced by other scripts
# and pipefail would cause premature exit when browser commands return non-zero.

# OpenELIS URLs and credentials
OPENELIS_BASE_URL="https://localhost"
OPENELIS_LOGIN_URL="${OPENELIS_BASE_URL}/login"
OPENELIS_DIRECT_URL="https://localhost:8443/api/OpenELIS-Global"
OPENELIS_USER="admin"
OPENELIS_PASS='adminADMIN!'
BROWSER_LOG_FILE="/tmp/browser_openelis_task.log"
BROWSER_CMD="firefox"

log() {
    echo "[openelis_task] $*"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

# ─── Service Readiness ───

wait_for_http() {
    local url="$1"
    local timeout_sec="${2:-600}"
    local elapsed=0

    log "Waiting for HTTP readiness: $url"

    while [ "$elapsed" -lt "$timeout_sec" ]; do
        local code
        code=$(curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "401" ] || [ "$code" = "403" ]; then
            log "HTTP ready after ${elapsed}s (HTTP $code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log "ERROR: Timeout waiting for HTTP readiness: $url"
    return 1
}

wait_for_openelis() {
    local timeout_sec="${1:-900}"
    wait_for_http "${OPENELIS_DIRECT_URL}/LoginPage" "$timeout_sec"
}

ensure_openelis_running() {
    log "Checking OpenELIS services..."

    local containers_running
    containers_running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c "openelis\|external-fhir" || echo "0")
    if [ "$containers_running" -lt 3 ]; then
        log "Restarting OpenELIS containers..."
        cd /home/ga/openelis
        if docker compose version >/dev/null 2>&1; then
            docker compose up -d 2>/dev/null || true
        else
            docker-compose up -d 2>/dev/null || true
        fi
        sleep 30
    fi

    wait_for_openelis 300
}

# ─── Window Management ───

get_browser_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null \
        | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; title=substr(title,2); print $1, title}' \
        | grep -iv '@!0,0' \
        | grep -i 'firefox\|mozilla\|openelis\|security\|warning\|localhost\|login\|home' \
        | awk '{print $1; exit}'
}

get_browser_window_id_any() {
    DISPLAY=:1 wmctrl -l 2>/dev/null \
        | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; title=substr(title,2); print $1, title}' \
        | grep -iv '@!0,0' \
        | grep -v '^$' \
        | awk '{print $1; exit}'
}

focus_window() {
    local window_id="$1"
    DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null \
        || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null \
        || return 1
    sleep 0.3
    return 0
}

maximize_active_window() {
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

focus_browser() {
    local wid
    wid=$(get_browser_window_id)
    if [ -z "$wid" ]; then
        wid=$(get_browser_window_id_any)
    fi
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        maximize_active_window
        return 0
    fi
    return 1
}

# ─── Screenshot ───

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    local wid
    wid=$(get_browser_window_id)
    if [ -z "$wid" ]; then
        wid=$(get_browser_window_id_any)
    fi
    if [ -n "$wid" ]; then
        DISPLAY=:1 xwd -id "$wid" -out /tmp/_ss.xwd 2>/dev/null \
            && convert /tmp/_ss.xwd "$output_file" 2>/dev/null \
            && rm -f /tmp/_ss.xwd 2>/dev/null \
            && return 0
    fi
    # Fallback to root window
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

# ─── Browser Management ───

stop_browser() {
    pkill -TERM -f 'firefox' 2>/dev/null || true
    local i=0
    while [ "$i" -lt 10 ]; do
        if pgrep -f 'firefox' >/dev/null 2>&1; then
            sleep 0.5
        else
            break
        fi
        i=$((i + 1))
    done
    pkill -KILL -f 'firefox' 2>/dev/null || true
    sleep 1

    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true
}

dismiss_ssl_warning() {
    local wid
    wid=$(get_browser_window_id)
    if [ -z "$wid" ]; then
        wid=$(get_browser_window_id_any)
    fi
    if [ -z "$wid" ]; then
        return 0
    fi

    focus_window "$wid" || true
    maximize_active_window
    sleep 1

    local win_title
    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
        | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)

    if echo "$win_title" | grep -qi "Firefox View"; then
        log "Firefox View detected, switching to SSL warning tab..."
        DISPLAY=:1 xdotool mousemove 160 65 click 1 2>/dev/null || true
        sleep 2
        win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
            | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
    fi

    if ! echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
        return 0
    fi

    log "SSL warning detected: $win_title"
    log "Dismissing with mouse clicks..."

    # Click "Advanced..." button: VG coords (879, 470) → scaled 1.5x to (1319, 705)
    DISPLAY=:1 xdotool mousemove 1319 705 click 1 2>/dev/null || true
    sleep 4

    # Click "Accept the Risk and Continue"
    DISPLAY=:1 xdotool mousemove 1319 800 click 1 2>/dev/null || true
    sleep 3

    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
        | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
    if echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
        log "First accept click didn't work, trying alternates..."
        DISPLAY=:1 xdotool mousemove 1200 790 click 1 2>/dev/null || true
        sleep 2
        DISPLAY=:1 xdotool mousemove 1100 810 click 1 2>/dev/null || true
        sleep 2
    fi

    return 0
}

navigate_to_url() {
    local url="$1"

    if ! has_command xdotool; then
        return 0
    fi

    local wid
    wid=$(get_browser_window_id)
    if [ -z "$wid" ]; then
        wid=$(get_browser_window_id_any)
    fi
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.3
    fi

    DISPLAY=:1 xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 20 --clearmodifiers "$url" 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
}

start_browser() {
    local url="$1"
    local attempts="${2:-3}"

    wait_for_openelis 120 || log "WARNING: OpenELIS may not be ready"

    for attempt in $(seq 1 "$attempts"); do
        log "Starting browser (attempt ${attempt}/${attempts}): $url"

        stop_browser
        pkill -9 -f firefox 2>/dev/null || true
        sleep 3

        find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
        find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
        find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
        find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true

        rm -f "$BROWSER_LOG_FILE" 2>/dev/null || true

        log "Launching Firefox as ga user"
        su - ga -c "DISPLAY=:1 setsid firefox '${url}' > '${BROWSER_LOG_FILE}' 2>&1 &"

        sleep 10
        local elapsed=0
        local wid=""
        while [ "$elapsed" -lt 50 ]; do
            wid=$(get_browser_window_id_any)
            if [ -n "$wid" ]; then
                break
            fi
            sleep 1
            elapsed=$((elapsed + 1))
        done

        if [ -z "$wid" ]; then
            log "Firefox window did not appear on attempt ${attempt}"
            continue
        fi

        focus_window "$wid" || true
        maximize_active_window
        sleep 2

        dismiss_ssl_warning
        sleep 2

        local cur_title
        cur_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
            | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
        if echo "$cur_title" | grep -qi "Firefox View\|New Tab\|about:"; then
            log "On Firefox View/New Tab, navigating to $url..."
            navigate_to_url "$url"
            sleep 8
            dismiss_ssl_warning
            sleep 2
        fi

        local page_wait=0
        local ssl_dismiss_attempts=0
        while [ "$page_wait" -lt 30 ]; do
            local title
            title=$(DISPLAY=:1 wmctrl -l 2>/dev/null \
                | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; print title}' \
                | grep -iv '@!0,0' | head -1)
            if echo "$title" | grep -qi "openelis\|home\|login\|localhost"; then
                break
            fi
            if echo "$title" | grep -qi "security\|warning\|risk"; then
                if [ "$ssl_dismiss_attempts" -lt 2 ]; then
                    dismiss_ssl_warning
                    ssl_dismiss_attempts=$((ssl_dismiss_attempts + 1))
                    sleep 3
                fi
            fi
            if echo "$title" | grep -qi "mozilla\|firefox"; then
                if ! echo "$title" | grep -qi "security\|warning\|risk\|error\|Firefox View\|New Tab"; then
                    break
                fi
            fi
            sleep 1
            page_wait=$((page_wait + 1))
        done

        local win_title
        win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null \
            | grep -v '@!0,0' \
            | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' \
            | head -1 | xargs)
        log "Browser ready (window: ${win_title})"
        return 0
    done

    log "ERROR: Failed to start browser after ${attempts} attempts"
    return 1
}

# Aliases
restart_firefox() { start_browser "$@"; }
restart_browser() { start_browser "$@"; }
focus_firefox() { focus_browser "$@"; }
launch_firefox() { start_browser "$@"; }

wait_for_page_load() {
    local wait_time="${1:-5}"
    sleep "$wait_time"
}

# ─── Database Queries ───

openelis_db_query() {
    local query="$1"
    docker exec openelisglobal-database psql -U clinlims -d clinlims -t -A -c "$query" 2>/dev/null
}

openelis_db_query_count() {
    local query="$1"
    local result
    result=$(openelis_db_query "$query" 2>/dev/null | tr -d '[:space:]')
    echo "${result:-0}"
}

# ─── REST API Helpers ───

openelis_api_login() {
    curl -sk -c /tmp/openelis_cookies.txt \
        "$OPENELIS_DIRECT_URL/LoginPage" -o /dev/null 2>/dev/null
    curl -sk -b /tmp/openelis_cookies.txt -c /tmp/openelis_cookies.txt \
        -d "loginName=$OPENELIS_USER&password=$OPENELIS_PASS" \
        "$OPENELIS_DIRECT_URL/ValidateLogin" -o /dev/null 2>/dev/null
    log "API login completed"
}

openelis_api_get() {
    local endpoint="$1"
    curl -sk -b /tmp/openelis_cookies.txt \
        "$OPENELIS_DIRECT_URL/$endpoint" 2>/dev/null
}

openelis_api_post() {
    local endpoint="$1"
    local data="$2"
    curl -sk -b /tmp/openelis_cookies.txt \
        -H "Content-Type: application/json" \
        -X POST -d "$data" \
        "$OPENELIS_DIRECT_URL/$endpoint" 2>/dev/null
}

# ─── Login via browser console (React apps don't work with xdotool typing) ───

ensure_logged_in() {
    local target_url="${1:-$OPENELIS_BASE_URL/}"

    log "Ensuring OpenELIS login..."

    navigate_to_url "$OPENELIS_LOGIN_URL"
    sleep 5

    # Use browser console to log in via fetch API (most reliable for React apps)
    DISPLAY=:1 xdotool key ctrl+shift+k 2>/dev/null || true
    sleep 2

    DISPLAY=:1 xdotool type --delay 10 --clearmodifiers "fetch('/api/OpenELIS-Global/ValidateLogin',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'loginName=admin&password=adminADMIN!',credentials:'include'}).then(r=>{console.log('Login:',r.status);window.location.href='${target_url}';});" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8

    # Close developer tools
    DISPLAY=:1 xdotool key F12 2>/dev/null || true
    sleep 2

    log "Login automation complete"
}

# ─── Export functions ───

export -f log
export -f wait_for_http
export -f wait_for_openelis
export -f ensure_openelis_running
export -f get_browser_window_id
export -f get_browser_window_id_any
export -f focus_window
export -f maximize_active_window
export -f focus_browser
export -f focus_firefox
export -f take_screenshot
export -f stop_browser
export -f dismiss_ssl_warning
export -f navigate_to_url
export -f start_browser
export -f restart_firefox
export -f restart_browser
export -f launch_firefox
export -f wait_for_page_load
export -f openelis_db_query
export -f openelis_db_query_count
export -f openelis_api_login
export -f openelis_api_get
export -f openelis_api_post
export -f ensure_logged_in

# Auto-check services when sourced
ensure_openelis_running
