#!/bin/bash
# Shared utilities for CalemEAM task setup and export scripts

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 30)
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

# Wait for a process to start
# Args: $1 - process name pattern (pgrep pattern)
#       $2 - timeout in seconds (default: 20)
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
# Args: $1 - window ID
focus_window() {
    local window_id="$1"
    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        echo "Window focused: $window_id"
        return 0
    fi
    echo "Failed to focus window: $window_id"
    return 1
}

# Get the window ID for Firefox
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
}

# Execute SQL query against CalemEAM database (via Docker)
# Args: $1 - SQL query
calemeam_query() {
    local query="$1"
    docker exec calemeam-mysql mysql -uroot -proot calemeam -N -e "$query" 2>/dev/null
}

# Execute SQL query with column headers
calemeam_query_verbose() {
    local query="$1"
    docker exec calemeam-mysql mysql -uroot -proot calemeam -e "$query" 2>/dev/null
}

# Take a screenshot
# Args: $1 - output file path (default: /tmp/screenshot.png)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# Export these functions
export -f wait_for_window
export -f wait_for_process
export -f focus_window
export -f get_firefox_window_id
export -f calemeam_query
export -f calemeam_query_verbose
export -f take_screenshot
