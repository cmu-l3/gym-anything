#!/bin/bash
# Shared utilities for all Visallo tasks

VISALLO_URL="http://localhost:8080"
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}

# Wait for Visallo web interface to be ready
ensure_visallo_ready() {
    local max_attempts=${1:-30}
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "$VISALLO_URL/" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "Visallo is ready (HTTP $HTTP_CODE)" >&2
            return 0
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    echo "WARNING: Visallo may not be ready (HTTP $HTTP_CODE)" >&2
    return 1
}

# Check if Elasticsearch is responsive
check_elasticsearch() {
    curl -s http://localhost:9200/_cluster/health 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unreachable"
}

# Ensure Firefox is running and pointed at the right URL
ensure_firefox() {
    local url="${1:-$VISALLO_URL/}"

    if ! pgrep -f firefox >/dev/null 2>&1; then
        echo "Firefox not running, launching..." >&2
        # Do NOT use --profile with snap Firefox
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox '$url' > /tmp/firefox_visallo.log 2>&1 &" 2>/dev/null
        sleep 5
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 2
    fi
}

# Kill Firefox cleanly and relaunch at URL
restart_firefox() {
    local url="${1:-$VISALLO_URL/}"

    pkill -KILL -f firefox 2>/dev/null || true
    pkill -KILL -f "Web Content" 2>/dev/null || true
    sleep 3

    # Clean ALL lock files (regular + snap locations)
    find /home/ga/.mozilla/ /home/ga/snap/firefox/ \
        -name "lock" -o -name ".parentlock" -o -name "parent.lock" \
        -o -name "singletonLock" -o -name "singletonCookie" -o -name "singletonSocket" \
        2>/dev/null | xargs rm -f 2>/dev/null || true

    # Do NOT use --profile with snap Firefox
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox '$url' > /tmp/firefox_visallo.log 2>&1 &" 2>/dev/null
    sleep 5

    # Wait for window
    for i in $(seq 1 15); do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|visallo"; then
            echo "Firefox window detected" >&2
            break
        fi
        sleep 1
    done

    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
}

# Log in to Visallo (username-only auth)
# Uses Escape+Tab approach because snap Firefox doesn't reliably accept
# direct coordinate clicks on SPA input fields
visallo_login() {
    local username="${1:-analyst}"

    sleep 3
    # Escape from any focused browser chrome (URL bar, etc.)
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape
    sleep 0.5
    # Tab repeatedly to reach the username input field
    for i in $(seq 1 10); do
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Tab
        sleep 0.3
    done
    # Type username
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 80 "$username"
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return
    sleep 8
}

# Get list of windows
list_windows() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null || true
}
