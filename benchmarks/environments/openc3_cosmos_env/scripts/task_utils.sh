#!/bin/bash
# Shared utilities for OpenC3 COSMOS tasks

# Configuration
OPENC3_URL="http://localhost:2900"
ADMIN_PASSWORD="Cosmos2024!"

# Get COSMOS auth token (in open-source COSMOS, the token IS the password)
get_cosmos_token() {
    if [ -f /home/ga/.cosmos_token ]; then
        cat /home/ga/.cosmos_token
    else
        echo "$ADMIN_PASSWORD"
    fi
}

# Call COSMOS JSON-RPC API (generic - no type param, safe for commands)
cosmos_api() {
    local method="$1"
    local params="$2"
    local token
    token=$(get_cosmos_token)

    curl -s -X POST "$OPENC3_URL/openc3-api/api" \
        -H "Content-Type: application/json" \
        -H "Authorization: $token" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[$params],\"id\":1,\"keyword_params\":{\"scope\":\"DEFAULT\"}}"
}

# Read a telemetry value
cosmos_tlm() {
    local tlm_point="$1"
    local token=$(get_cosmos_token)

    curl -s -X POST "$OPENC3_URL/openc3-api/api" \
        -H "Content-Type: application/json" \
        -H "Authorization: $token" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"tlm\",\"params\":[\"$tlm_point\"],\"id\":1,\"keyword_params\":{\"type\":\"FORMATTED\",\"scope\":\"DEFAULT\"}}" | jq -r '.result'
}

# Send a command (bypasses hazardous confirmation that would block API calls)
cosmos_cmd() {
    local cmd_string="$1"
    local token=$(get_cosmos_token)

    curl -s -X POST "$OPENC3_URL/openc3-api/api" \
        -H "Content-Type: application/json" \
        -H "Authorization: $token" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"cmd_no_hazardous_check\",\"params\":[\"$cmd_string\"],\"id\":1,\"keyword_params\":{\"scope\":\"DEFAULT\"}}"
}

# Wait for COSMOS API to be ready
wait_for_cosmos_api() {
    local timeout=${1:-120}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "$OPENC3_URL/openc3-api/api" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"get_target_list","params":[],"id":1,"keyword_params":{"scope":"DEFAULT"}}' \
            2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for Firefox window
wait_for_window() {
    local pattern="${1:-firefox}"
    local timeout="${2:-30}"
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
    DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local wid="$1"
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

# Navigate Firefox to a URL by clicking the address bar directly
# Note: Ctrl+L is intercepted by COSMOS tools (Command Sender, Script Runner)
# so we click the address bar area instead
navigate_to_url() {
    local url="$1"
    # Click on the Firefox address bar
    # 1280x720 coordinates: (320, 85) -> 1920x1080: (480, 128)
    DISPLAY=:1 xdotool mousemove 480 128 click 1
    sleep 0.5
    # Select all text in address bar and replace
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.2
    DISPLAY=:1 xdotool type --delay 20 "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 3
}

# Wait for page load (check for specific text in page title)
wait_for_page_title() {
    local pattern="$1"
    local timeout="${2:-30}"
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
