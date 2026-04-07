#!/bin/bash
# Shared utilities for Angry IP Scanner task setup and export scripts

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
        if DISPLAY=:1 wmctrl -l | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s"
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
        if pgrep -c -f "$process_pattern" > /dev/null 2>&1; then
            echo "Process found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Process not found after ${timeout}s"
    return 1
}

# Focus a window by name pattern and maximize it
# Args: $1 - window name pattern
focus_and_maximize() {
    local window_pattern="$1"
    DISPLAY=:1 wmctrl -r "$window_pattern" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "$window_pattern" 2>/dev/null || true
    sleep 0.5
}

# Kill all ipscan processes
kill_ipscan() {
    echo "Killing Angry IP Scanner processes..."
    pkill -f ipscan 2>/dev/null || true
    sleep 2
}

# Check if ipscan is running
is_ipscan_running() {
    pgrep -c -f "ipscan" > /dev/null 2>&1
    return $?
}

# Get the window ID for Angry IP Scanner
get_ipscan_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i 'Angry IP Scanner\|ipscan' | awk '{print $1; exit}'
}

# Wait for a file to be created
# Args: $1 - file path
#       $2 - timeout in seconds (default: 10)
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local elapsed=0

    echo "Waiting for file: $filepath"

    while [ $elapsed -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            echo "File ready: $filepath"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: File not found: $filepath"
    return 1
}

# Dismiss any startup dialogs (Getting Started, etc.)
# SWT dialogs do NOT respond to xdotool key Escape; use wmctrl -c instead
dismiss_ipscan_dialogs() {
    local timeout=${1:-10}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "Getting Started"; then
            echo "Dismissing Getting Started dialog..."
            DISPLAY=:1 wmctrl -c "Getting Started" 2>/dev/null || true
            sleep 1
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "No startup dialogs detected"
    return 0
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_process
export -f focus_and_maximize
export -f kill_ipscan
export -f is_ipscan_running
export -f get_ipscan_window_id
export -f wait_for_file
export -f dismiss_ipscan_dialogs
