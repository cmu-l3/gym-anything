#!/bin/bash
# task_utils.sh — Shared utilities for all emoncms_env tasks
# Source this file: source /workspace/scripts/task_utils.sh
# NOTE: Do NOT use set -e / set -u in this file or callers (pattern #25)

XAUTH="/run/user/1000/gdm/Xauthority"
EMONCMS_URL="http://localhost"
EMONCMS_ADMIN_USER="admin"
EMONCMS_ADMIN_PASS="admin"
EMONCMS_PROFILE="/home/ga/snap/firefox/common/.mozilla/firefox/emoncms.profile"

# Load API keys if available
if [ -f /home/ga/emoncms_apikeys.sh ]; then
    source /home/ga/emoncms_apikeys.sh
fi

# -----------------------------------------------------------------------
# Get API key from database
# -----------------------------------------------------------------------
get_apikey_write() {
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N \
        -e "SELECT apikey_write FROM users WHERE username='admin'" 2>/dev/null | head -1
}

get_apikey_read() {
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N \
        -e "SELECT apikey_read FROM users WHERE username='admin'" 2>/dev/null | head -1
}

# -----------------------------------------------------------------------
# Screenshot utility (GNOME-safe: xwd + convert, NOT scrot/import)
# -----------------------------------------------------------------------
take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    local raw_xwd
    raw_xwd=$(mktemp /tmp/xwd_XXXXXX.xwd)
    DISPLAY=:1 XAUTHORITY="${XAUTH}" xwd -root -silent -out "$raw_xwd" 2>/dev/null \
        && convert "$raw_xwd" "$output" 2>/dev/null \
        || echo "Warning: screenshot failed"
    rm -f "$raw_xwd"
    echo "$output"
}

# -----------------------------------------------------------------------
# Emoncms API call helper
# Usage: emoncms_api "feed/list.json" "apikey=XXXX&param=val"
# -----------------------------------------------------------------------
emoncms_api() {
    local endpoint="$1"
    local params="${2:-}"
    local apikey
    apikey=$(get_apikey_write)
    local url="${EMONCMS_URL}/${endpoint}?apikey=${apikey}"
    if [ -n "$params" ]; then
        url="${url}&${params}"
    fi
    curl -s "$url" 2>/dev/null
}

# -----------------------------------------------------------------------
# MySQL query helper
# -----------------------------------------------------------------------
db_query() {
    local query="$1"
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e "$query" 2>/dev/null
}

# -----------------------------------------------------------------------
# Wait for Emoncms to be reachable
# -----------------------------------------------------------------------
wait_for_emoncms() {
    local url="${EMONCMS_URL}/"
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "Warning: Emoncms not reachable after ${timeout}s"
    return 1
}

# -----------------------------------------------------------------------
# Launch Firefox at a given URL (handles cold start + snap permissions)
# Always logs in to Emoncms before navigating to the target URL.
# -----------------------------------------------------------------------
launch_firefox_to() {
    local url="${1:-http://localhost/}"
    local wait_sec="${2:-5}"

    # Wait for Emoncms web service to be ready before launching Firefox
    wait_for_emoncms || echo "WARNING: Emoncms may not be ready, attempting Firefox launch anyway"

    # Fix snap permissions
    chown -R ga:ga /home/ga/snap/ 2>/dev/null || true

    # Kill any stale Firefox
    pkill -9 -f firefox 2>/dev/null || true
    for i in $(seq 1 10); do
        pgrep -f firefox >/dev/null 2>&1 || break
        sleep 1
    done
    sleep 2

    # Remove lock files and launch Firefox to the login page first
    sudo -u ga bash -c "
        rm -f ${EMONCMS_PROFILE}/.parentlock ${EMONCMS_PROFILE}/lock 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=${XAUTH} \
        setsid firefox --new-instance \
            -profile ${EMONCMS_PROFILE} \
            'http://localhost/user/login' &
    "

    # Wait for Firefox window to appear (up to 60s)
    for _i in $(seq 1 30); do
        if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -qi "mozilla\|firefox"; then
            echo "Firefox window appeared"
            break
        fi
        sleep 2
    done
    sleep 6

    # Maximize
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1

    # Log in: username field has autofocus on /user/login
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers '${EMONCMS_ADMIN_USER}'" 2>/dev/null || true
    sleep 0.3
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab" 2>/dev/null || true
    sleep 0.3
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers '${EMONCMS_ADMIN_PASS}'" 2>/dev/null || true
    sleep 0.3
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return" 2>/dev/null || true
    sleep 5  # Wait for AJAX login + redirect

    # Navigate to the target URL
    if [ "$url" != "http://localhost/user/login" ]; then
        navigate_to "$url" "$wait_sec"
    fi
}

# -----------------------------------------------------------------------
# Navigate Firefox to a URL (Firefox must already be running)
# -----------------------------------------------------------------------
navigate_to() {
    local url="$1"
    local wait_sec="${2:-3}"

    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -a "Mozilla Firefox" 2>/dev/null || true
    sleep 0.5

    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key ctrl+l" 2>/dev/null || true
    sleep 0.3
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers '${url}'" 2>/dev/null || true
    sleep 0.2
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return" 2>/dev/null || true
    sleep "$wait_sec"
}

# -----------------------------------------------------------------------
# Maximize Firefox window
# -----------------------------------------------------------------------
maximize_firefox() {
    sleep 1
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

export -f take_screenshot
export -f get_apikey_write
export -f get_apikey_read
export -f emoncms_api
export -f db_query
export -f wait_for_emoncms
export -f launch_firefox_to
export -f navigate_to
export -f maximize_firefox
