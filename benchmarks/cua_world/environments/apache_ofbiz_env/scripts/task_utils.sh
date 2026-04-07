#!/bin/bash
# Shared utilities for all Apache OFBiz tasks

OFBIZ_URL="https://localhost:8443"
ADMIN_USER="admin"
ADMIN_PASS="ofbiz"
CONTAINER_NAME="ofbiz"

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for OFBiz to respond (uses -k to skip SSL cert verification)
wait_for_ofbiz() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$OFBIZ_URL/accounting/control/main" 2>/dev/null)
        # 401 means OFBiz is running but requires auth — it's ready
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ] || [ "$HTTP_CODE" = "401" ]; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

# Login to OFBiz via URL parameters (OFBiz supports URL-based auth)
ofbiz_login_url() {
    local target_url="$1"
    echo "${target_url}?USERNAME=${ADMIN_USER}&PASSWORD=${ADMIN_PASS}&JavaScriptEnabled=Y"
}

# Handle browser SSL certificate warning via developer console
handle_ssl_warning() {
    local TITLE
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
    if echo "$TITLE" | grep -qi "warning\|risk\|cert\|error\|secure"; then
        echo "SSL certificate warning detected, accepting via console..."
        # Open developer console
        DISPLAY=:1 xdotool key ctrl+shift+k
        sleep 3
        # Click Advanced button via DOM
        DISPLAY=:1 xdotool type --clearmodifiers 'document.getElementById("advancedButton").click()'
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 2
        # Click Accept the Risk and Continue
        DISPLAY=:1 xdotool type --clearmodifiers 'document.getElementById("exceptionDialogButton").click()'
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 5
        # Close developer console
        DISPLAY=:1 xdotool key F12
        sleep 1
        echo "SSL certificate accepted"
        return 0
    fi
    return 1
}

# Handle OFBiz login page if we land on it
handle_ofbiz_login() {
    echo "Attempting OFBiz login via browser..."
    sleep 2
    # OFBiz login form has USERNAME and PASSWORD fields
    # Use Tab to navigate: first field is USERNAME
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 5
    echo "Login form submitted"
}

# Ensure Firefox is running and navigate to a URL (with auth)
ensure_firefox_at() {
    local url="$1"
    local auth_url
    auth_url=$(ofbiz_login_url "$url")

    local FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
    if [ -z "$FIREFOX_PID" ]; then
        # Clean stale lock files before launching
        pkill -9 -f firefox 2>/dev/null || true
        sleep 1
        rm -f /home/ga/.mozilla/firefox/default-release/.parentlock \
              /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
        su - ga -c "DISPLAY=:1 firefox '$auth_url' &" 2>/dev/null
        sleep 5
    else
        # Use xdotool to navigate
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "$auth_url"
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

    # Handle SSL warning if present
    sleep 3
    handle_ssl_warning

    # Check if we're on a login page
    sleep 2
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
    if echo "$TITLE" | grep -qi "login"; then
        handle_ofbiz_login
        # Re-navigate after login
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "$url"
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 3
    fi
}

# ---------------------------------------------------------------
# Ensure OFBiz services are running
# Critical when loading from QEMU checkpoint
# ---------------------------------------------------------------
ensure_ofbiz_running() {
    # Quick check: is OFBiz already responding?
    local http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "$OFBIZ_URL/accounting/control/main" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "303" ] || [ "$http_code" = "401" ]; then
        echo "OFBiz already running (HTTP $http_code)"
        return 0
    fi

    echo "OFBiz not responding (HTTP $http_code). Starting services..."

    # Ensure Docker daemon is running
    systemctl is-active docker >/dev/null 2>&1 || {
        echo "Starting Docker daemon..."
        systemctl start docker
        sleep 5
    }

    # Start the OFBiz container
    docker start "$CONTAINER_NAME" 2>/dev/null || {
        echo "Container not found, creating new one..."
        docker run -d \
            --name "$CONTAINER_NAME" \
            -e OFBIZ_DATA_LOAD=demo \
            -e OFBIZ_ADMIN_USER="$ADMIN_USER" \
            -e OFBIZ_ADMIN_PASSWORD="$ADMIN_PASS" \
            -p 8443:8443 \
            -p 8080:8080 \
            ghcr.io/apache/ofbiz:release24.09-plugins-snapshot || \
        docker run -d \
            --name "$CONTAINER_NAME" \
            -e OFBIZ_DATA_LOAD=demo \
            -e OFBIZ_ADMIN_USER="$ADMIN_USER" \
            -e OFBIZ_ADMIN_PASSWORD="$ADMIN_PASS" \
            -p 8443:8443 \
            -p 8080:8080 \
            ghcr.io/apache/ofbiz:trunk-plugins-snapshot
    }

    # Poll for HTTP readiness (up to 300s)
    local timeout=300
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "$OFBIZ_URL/accounting/control/main" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "303" ] || [ "$http_code" = "401" ]; then
            echo "OFBiz is ready after ${elapsed}s (HTTP $http_code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting for OFBiz... ${elapsed}s (HTTP $http_code)"
        fi
    done

    echo "WARNING: OFBiz may not be ready after ${timeout}s (HTTP $http_code)"
    return 0
}

# Auto-start services when task_utils.sh is sourced
ensure_ofbiz_running
