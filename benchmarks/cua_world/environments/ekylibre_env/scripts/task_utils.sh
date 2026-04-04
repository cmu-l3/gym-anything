#!/bin/bash
# Ekylibre task utilities - shared functions for all task setup scripts
# Source this from setup_task.sh files:
#   source /workspace/scripts/task_utils.sh

EKYLIBRE_URL="http://demo.ekylibre.farm:3000"
EKYLIBRE_FALLBACK_URL="http://demo.ekylibre.local:3000"
ADMIN_EMAIL="admin@ekylibre.org"
ADMIN_PASSWORD="12345678"

# Detect the actual working URL
detect_ekylibre_url() {
    for URL in "$EKYLIBRE_URL" "$EKYLIBRE_FALLBACK_URL" "http://demo.ekylibre.lan:3000" "http://default.ekylibre.lan:3000" "http://localhost:3000"; do
        code=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
            echo "$URL"
            return 0
        fi
    done
    # Default to demo URL
    echo "$EKYLIBRE_URL"
}

# Wait for Ekylibre to be accessible
wait_for_ekylibre() {
    local timeout="${1:-120}"
    local elapsed=0
    local url

    url=$(detect_ekylibre_url)

    echo "Waiting for Ekylibre at $url..."
    while [ "$elapsed" -lt "$timeout" ]; do
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
            echo "Ekylibre ready (HTTP $code) after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "WARNING: Ekylibre may not be ready (timeout ${timeout}s)"
    return 1
}

# Ensure Firefox is running with Ekylibre
ensure_firefox_with_ekylibre() {
    local url="${1:-}"
    if [ -z "$url" ]; then
        url=$(detect_ekylibre_url)
    fi

    # Check if Firefox is running
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        # Firefox is running - navigate to URL
        local WID
        WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
              xdotool search --class Firefox 2>/dev/null | tail -1)
        if [ -n "$WID" ]; then
            # Focus window and navigate
            DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool windowactivate "$WID" 2>/dev/null || true
            sleep 0.5
            DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" ctrl+l 2>/dev/null || true
            sleep 0.3
            DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers "$url" 2>/dev/null || true
            DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" Return 2>/dev/null || true
        fi
    else
        # Firefox not running — launch it
        pkill -f firefox 2>/dev/null || true
        sleep 1

        SNAP_FF_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
        STD_FF_DIR="/home/ga/.mozilla/firefox"

        if [ -d "/snap/firefox" ] || snap list firefox 2>/dev/null | grep -q firefox; then
            su - ga -c "
                rm -f '$SNAP_FF_DIR/ekylibre.profile/.parentlock' \
                      '$SNAP_FF_DIR/ekylibre.profile/lock' 2>/dev/null || true
                DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
                setsid firefox --new-instance \
                -profile '$SNAP_FF_DIR/ekylibre.profile' \
                '$url' > /tmp/firefox_task.log 2>&1 &
            "
        else
            su - ga -c "
                DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
                XDG_RUNTIME_DIR=/run/user/1000 \
                DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
                setsid firefox \
                -profile '$STD_FF_DIR/ekylibre.profile' \
                '$url' > /tmp/firefox_task.log 2>&1 &
            "
        fi

        # Wait for Firefox
        for i in $(seq 1 20); do
            if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
                break
            fi
            sleep 1
        done
    fi

    sleep 3
}

# Maximize Firefox window
maximize_firefox() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5
}

# Navigate Firefox to a specific URL
navigate_to() {
    local url="$1"
    local WID
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
          xdotool search --class Firefox 2>/dev/null | tail -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" ctrl+l 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers "$url" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key --window "$WID" Return 2>/dev/null || true
        sleep 3
    fi
}

# Query Ekylibre database
ekylibre_db_query() {
    local query="$1"
    docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "$query" 2>/dev/null \
        || echo ""
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root "$path" 2>/dev/null || true
}
