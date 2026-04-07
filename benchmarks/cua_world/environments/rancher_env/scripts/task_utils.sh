#!/bin/bash
# Shared utilities for Rancher environment tasks

RANCHER_URL="https://localhost"
ADMIN_USER="admin"
ADMIN_PASS="Admin12345678!"

# Get an API token from Rancher
get_rancher_token() {
    curl -sk "$RANCHER_URL/v3-public/localProviders/local?action=login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\",\"responseType\":\"token\"}" 2>/dev/null | jq -r '.token // empty'
}

# Wait for Rancher API to be accessible
wait_for_rancher_api() {
    local timeout=${1:-60}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$RANCHER_URL/v3" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

# Wait for a specific window to appear
wait_for_window() {
    local pattern="$1"
    local timeout=${2:-30}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local wid="$1"
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    sleep 0.5
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Run kubectl inside the Rancher container
rancher_kubectl() {
    docker exec rancher kubectl "$@" 2>/dev/null
}
