#!/bin/bash
# Shared utilities for OpenEMR task setup and export scripts

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

# Execute SQL query against OpenEMR database (via Docker)
# Args: $1 - SQL query
# Returns: query result
openemr_query() {
    local query="$1"
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "$query" 2>/dev/null
}

# Get patient count from database
get_patient_count() {
    openemr_query "SELECT COUNT(*) FROM patient_data"
}

# Check if patient exists by name
# Args: $1 - first name, $2 - last name
# Returns: 0 if found, 1 if not found
patient_exists() {
    local fname="$1"
    local lname="$2"
    local count=$(openemr_query "SELECT COUNT(*) FROM patient_data WHERE fname='$fname' AND lname='$lname'")
    [ "$count" -gt 0 ]
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
export -f openemr_query
export -f get_patient_count
export -f patient_exists
export -f take_screenshot
