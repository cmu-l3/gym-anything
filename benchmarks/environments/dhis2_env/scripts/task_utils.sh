#!/bin/bash
# Shared utilities for DHIS2 task setup and export scripts

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 30)
# Returns: 0 if found, 1 if timeout
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s"
    return 1
}

# Wait for a file to be created or modified
# Args: $1 - file path
#       $2 - timeout in seconds (default: 10)
# Returns: 0 if file exists and was recently modified, 1 if timeout
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            if [ $(find "$filepath" -mmin -0.2 2>/dev/null | wc -l) -gt 0 ] || \
               [ $(($(date +%s) - start)) -lt 2 ]; then
                echo "File ready: $filepath"
                return 0
            fi
        fi
        sleep 0.5
    done

    echo "Timeout: File not updated: $filepath"
    return 1
}

# Wait for a process to start
# Args: $1 - process name pattern (pgrep pattern)
#       $2 - timeout in seconds (default: 20)
# Returns: 0 if process found, 1 if timeout
wait_for_process() {
    local process_pattern="$1"
    local timeout=${2:-20}
    local elapsed=0

    echo "Waiting for process matching '$process_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_pattern" > /dev/null; then
            echo "Process found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Process not found after ${timeout}s"
    return 1
}

# Focus a window and verify it was focused
# Args: $1 - window ID or name pattern
# Returns: 0 if focused successfully, 1 otherwise
focus_window() {
    local window_id="$1"

    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        if DISPLAY=:1 wmctrl -lpG 2>/dev/null | grep -q "$window_id"; then
            echo "Window focused: $window_id"
            return 0
        fi
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the window ID for Firefox
# Returns: window ID or empty string
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
}

# Safe xdotool command with display and user context
# Args: $1 - user (e.g., "ga")
#       $2 - display (e.g., ":1")
#       rest - xdotool arguments
safe_xdotool() {
    local user="$1"
    local display="$2"
    shift 2

    su - "$user" -c "DISPLAY=$display xdotool $*" 2>&1 | grep -v "^$"
    return ${PIPESTATUS[0]}
}

# Execute SQL query against DHIS2 database (via Docker)
# Args: $1 - SQL query
# Returns: query result
dhis2_query() {
    local query="$1"
    docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$query" 2>/dev/null
}

# Execute DHIS2 API call (authenticated)
# Args: $1 - API endpoint (e.g., "system/info")
#       $2 - HTTP method (default: GET)
# Returns: JSON response
dhis2_api() {
    local endpoint="$1"
    local method="${2:-GET}"
    curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
}

# Get count of tracked entity instances
get_tracked_entity_count() {
    dhis2_query "SELECT COUNT(*) FROM trackedentityinstance"
}

# Check if DHIS2 is running and responsive
check_dhis2_health() {
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$http_code" = "200" ] || [ "$http_code" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $http_code)"
        return 0
    fi
    echo "DHIS2 is not responsive (HTTP $http_code)"
    return 1
}

# Take a screenshot
# Args: $1 - output file path (default: /tmp/screenshot.png)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    # Use ImageMagick's import command (more reliable than scrot)
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f focus_window
export -f get_firefox_window_id
export -f safe_xdotool
export -f dhis2_query
export -f dhis2_api
export -f get_tracked_entity_count
export -f check_dhis2_health
export -f take_screenshot
