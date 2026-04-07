#!/bin/bash
# Shared utilities for all ERPNext tasks

ERPNEXT_URL="http://localhost:8080"
ADMIN_USER="Administrator"
ADMIN_PASS="admin"

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Login to ERPNext and store cookies
erpnext_login() {
    curl -s -c /tmp/erpnext_cookies.txt -b /tmp/erpnext_cookies.txt \
        -X POST "$ERPNEXT_URL/api/method/login" \
        -H "Content-Type: application/json" \
        -d "{\"usr\": \"$ADMIN_USER\", \"pwd\": \"$ADMIN_PASS\"}" > /dev/null 2>&1
}

# ERPNext API GET call
erpnext_get() {
    local endpoint="$1"
    curl -s -b /tmp/erpnext_cookies.txt "$ERPNEXT_URL/api/$endpoint" 2>/dev/null
}

# ERPNext API POST call
erpnext_post() {
    local endpoint="$1"
    local data="$2"
    curl -s -b /tmp/erpnext_cookies.txt \
        -X POST "$ERPNEXT_URL/api/$endpoint" \
        -H "Content-Type: application/json" \
        -d "$data" 2>/dev/null
}

# Wait for ERPNext to respond
wait_for_erpnext() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ERPNEXT_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

# Handle browser login if redirected to login page
handle_browser_login() {
    echo "Browser redirected to login page, authenticating..."
    sleep 2
    # Click email field area and type credentials
    DISPLAY=:1 xdotool mousemove 994 414 click 1
    sleep 1
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers 'Administrator'
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers 'admin'
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 8
    echo "Browser login completed"
}

# Ensure Firefox is running and navigate to a URL
ensure_firefox_at() {
    local url="$1"
    local FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
    if [ -z "$FIREFOX_PID" ]; then
        # Clean stale lock files before launching
        pkill -9 -f firefox 2>/dev/null || true
        sleep 1
        rm -f /home/ga/.mozilla/firefox/default-release/.parentlock \
              /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
        su - ga -c "DISPLAY=:1 firefox '$url' &" 2>/dev/null
        sleep 5
    else
        # Use xdotool to navigate - open URL in current tab
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "$url"
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 3
    fi

    # Wait for Firefox window and maximize
    for i in {1..15}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
            WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
            if [ -n "$WID" ]; then
                DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
                DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
            fi
            break
        fi
        sleep 1
    done

    # Safety check: if we ended up on the login page, authenticate first
    sleep 3
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
    if echo "$TITLE" | grep -qi "login"; then
        handle_browser_login
        # After login, navigate to the intended URL
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "$url"
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 3
    fi
}

# ---------------------------------------------------------------
# Ensure ERPNext services are running
# Critical when loading from QEMU checkpoint — Docker containers
# that were running during checkpoint creation are NOT running
# when the checkpoint is restored.
# ---------------------------------------------------------------
ensure_erpnext_running() {
    # Quick check: is ERPNext already responding?
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ERPNEXT_URL" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "303" ]; then
        echo "ERPNext already running (HTTP $http_code)"
        return 0
    fi

    echo "ERPNext not responding (HTTP $http_code). Starting services..."

    # Ensure Docker daemon is running
    systemctl is-active docker >/dev/null 2>&1 || {
        echo "Starting Docker daemon..."
        systemctl start docker
        sleep 5
    }

    # Determine compose command
    local COMPOSE_CMD=""
    if command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version &>/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        echo "ERROR: No docker-compose command found"
        return 1
    fi

    # Start containers from the ERPNext working directory
    local ERPNEXT_DIR="/home/ga/erpnext"
    if [ -f "$ERPNEXT_DIR/docker-compose.yml" ]; then
        echo "Starting ERPNext containers via $COMPOSE_CMD..."
        cd "$ERPNEXT_DIR"
        $COMPOSE_CMD up -d 2>&1 || true
        cd - >/dev/null
    else
        echo "ERROR: docker-compose.yml not found at $ERPNEXT_DIR"
        return 1
    fi

    # Poll for HTTP readiness (up to 180s)
    local timeout=180
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ERPNEXT_URL" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "303" ]; then
            echo "ERPNext is ready after ${elapsed}s (HTTP $http_code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting for ERPNext... ${elapsed}s (HTTP $http_code)"
        fi
    done

    echo "WARNING: ERPNext may not be ready after ${timeout}s (HTTP $http_code)"
    return 0
}

# Auto-start services when task_utils.sh is sourced
ensure_erpnext_running
