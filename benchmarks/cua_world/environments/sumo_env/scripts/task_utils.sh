#!/bin/bash
# Shared utilities for SUMO task setup and export scripts

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
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s"
    return 1
}

# Wait for a process to start
# Args: $1 - process name pattern
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
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Process not found after ${timeout}s"
    return 1
}

# Kill SUMO-related processes
kill_sumo() {
    echo "Killing SUMO processes..."
    pkill -f "sumo-gui" 2>/dev/null || true
    pkill -f "sumo " 2>/dev/null || true
    pkill -f "netedit" 2>/dev/null || true
    sleep 1
}

# Check if sumo-gui is running
is_sumo_gui_running() {
    pgrep -f "sumo-gui" > /dev/null
    return $?
}

# Check if netedit is running
is_netedit_running() {
    pgrep -f "netedit" > /dev/null
    return $?
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Focus and maximize a window by title pattern
focus_and_maximize() {
    local pattern="$1"
    local wid
    wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "$pattern" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 0.3
        echo "Window focused and maximized: $wid"
        return 0
    fi
    echo "Window not found for pattern: $pattern"
    return 1
}

# Export these functions
export -f wait_for_window
export -f wait_for_process
export -f kill_sumo
export -f is_sumo_gui_running
export -f is_netedit_running
export -f take_screenshot
export -f focus_and_maximize
