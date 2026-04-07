#!/bin/bash
# Shared utilities for KNIME Analytics Platform task setup scripts

KNIME_DIR="/opt/knime"
KNIME_WORKSPACE="/home/ga/knime-workspace"

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 60)
# Returns: 0 if found, 1 if timeout
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-60}
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

# Wait for a file to be created or modified
# Args: $1 - file path
#       $2 - timeout in seconds (default: 10)
# Returns: 0 if file exists, 1 if timeout
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            echo "File ready: $filepath"
            return 0
        fi
        sleep 0.5
    done

    echo "Timeout: File not found: $filepath"
    return 1
}

# Wait for a process to start
# Args: $1 - process name pattern (pgrep pattern)
#       $2 - timeout in seconds (default: 30)
# Returns: 0 if process found, 1 if timeout
wait_for_process() {
    local process_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for process matching '$process_pattern'..."

    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_pattern" > /dev/null 2>&1; then
            echo "Process found after ${elapsed}s"
            return 0
        fi
        sleep 1
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
        echo "Window focused: $window_id"
        return 0
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the KNIME main window ID
# Returns: window ID or empty string
get_knime_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'KNIME' | awk '{print $1; exit}'
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

# Kill KNIME and all related processes, clean up lock files
kill_knime() {
    pkill -u ga -f "knime" 2>/dev/null || true
    pkill -u ga -f "eclipse" 2>/dev/null || true
    pkill -u ga -f "equochro" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    pkill -9 -u ga -f "knime" 2>/dev/null || true
    pkill -9 -u ga -f "eclipse" 2>/dev/null || true
    pkill -9 -u ga -f "java.*knime" 2>/dev/null || true
    pkill -9 -u ga -f "equochro" 2>/dev/null || true
    sleep 2

    # CRITICAL: Remove workspace lock file so KNIME can relaunch
    rm -f "$KNIME_WORKSPACE/.metadata/.lock"
    rm -f "$KNIME_WORKSPACE/.metadata/.plugins/org.eclipse.core.resources/.snap"
}

# Launch KNIME for a task
# Args: none (uses global KNIME_DIR and KNIME_WORKSPACE)
# Returns: 0 if KNIME started, 1 otherwise
launch_knime() {
    echo "Launching KNIME Analytics Platform..."

    # Kill any existing KNIME instances and clean up lock files
    kill_knime

    # Launch KNIME with workspace and XAUTHORITY set explicitly
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority nohup $KNIME_DIR/knime -data $KNIME_WORKSPACE > /tmp/knime_task.log 2>&1 &"

    # Wait for KNIME window to appear (Java app, may take 30-90s)
    if ! wait_for_window "KNIME" 120; then
        echo "ERROR: KNIME window did not appear"
        echo "KNIME log:"
        cat /tmp/knime_task.log 2>/dev/null | tail -30
        return 1
    fi

    # Give KNIME extra time to fully initialize after window appears
    sleep 8

    # Dismiss the "Help Improve KNIME" telemetry dialog (appears on first launch after workspace reset)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize the window
    DISPLAY=:1 wmctrl -r "KNIME" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2

    echo "KNIME launched successfully"
    return 0
}

# Create a new empty workflow in KNIME
# Args: $1 - workflow name (e.g., "Titanic Analysis")
# Returns: 0 if workflow created, 1 otherwise
# NOTE: Coordinates are calibrated for 1920x1080 maximized KNIME window
create_new_workflow() {
    local workflow_name="$1"

    echo "Creating new workflow: $workflow_name"

    # Click the golden "Create new workflow" button on the Welcome page
    # Coordinates: (1806, 472) at 1920x1080 with maximized KNIME window
    DISPLAY=:1 xdotool mousemove 1806 472
    sleep 0.5
    DISPLAY=:1 xdotool click 1
    sleep 3

    # The "Create a new workflow" dialog should appear with a text field
    # Select all text in the name field and type the new name
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$workflow_name"
    sleep 1

    # Click the golden "Create" button in the dialog
    # Coordinates: (1141, 536) at 1920x1080
    DISPLAY=:1 xdotool mousemove 1141 536
    sleep 0.5
    DISPLAY=:1 xdotool click 1
    sleep 5

    echo "Workflow '$workflow_name' created"
    return 0
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

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f focus_window
export -f get_knime_window_id
export -f safe_xdotool
export -f kill_knime
export -f launch_knime
export -f create_new_workflow
export -f take_screenshot
export KNIME_DIR
export KNIME_WORKSPACE
