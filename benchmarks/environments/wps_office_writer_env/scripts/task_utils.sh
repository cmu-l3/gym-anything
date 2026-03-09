#!/bin/bash
# Shared utilities for WPS Office Writer task setup and export scripts

# Set display for X11 commands
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

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
        if wmctrl -l | grep -qi "$window_pattern"; then
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

    if wmctrl -ia "$window_id" 2>/dev/null || wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        echo "Window focused: $window_id"
        return 0
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the window ID for WPS Writer
# Returns: window ID or empty string
get_wps_window_id() {
    wmctrl -l | grep -i 'WPS Writer\|\.docx\|\.doc\|\.wps\|wps$' | awk '{print $1; exit}'
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

# Dismiss WPS EULA/License Agreement dialog
# This dialog appears on first run and must be accepted
# VERIFIED COORDINATES for 1920x1080:
#   - Checkbox: (645, 648) - click to check "I have read and agreed"
#   - I Confirm button: (1266, 648) - click to dismiss dialog
# These coordinates were verified via ask_cua.py testing
dismiss_wps_eula() {
    local max_attempts=${1:-10}
    local attempt=0

    echo "Checking for WPS EULA dialog..."

    while [ $attempt -lt $max_attempts ]; do
        # Check if the license dialog is present
        local license_window=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "License Agreement\|Kingsoft Office Software\|End User License")

        if [ -n "$license_window" ]; then
            echo "EULA dialog detected, attempting to dismiss (attempt $((attempt+1)))..."

            # Focus the EULA window first
            local window_id=$(echo "$license_window" | awk '{print $1}')
            DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || true
            sleep 0.5

            # VERIFIED coordinates for 1920x1080 resolution (from ask_cua.py testing)
            # Checkbox at (430, 432) in 1280x720 scale = (645, 648) in 1920x1080
            # I Confirm button at (844, 432) in 1280x720 scale = (1266, 648) in 1920x1080

            # Step 1: Click the checkbox to check it
            echo "Clicking checkbox at (645, 648)..."
            DISPLAY=:1 xdotool mousemove 645 648 2>/dev/null || true
            sleep 0.2
            DISPLAY=:1 xdotool click 1 2>/dev/null || true
            sleep 0.5

            # Step 2: Click the "I Confirm" button
            echo "Clicking 'I Confirm' button at (1266, 648)..."
            DISPLAY=:1 xdotool mousemove 1266 648 2>/dev/null || true
            sleep 0.2
            DISPLAY=:1 xdotool click 1 2>/dev/null || true
            sleep 1.5

            # Check if dialog was dismissed
            if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "License Agreement\|Kingsoft Office Software\|End User License"; then
                echo "EULA dialog dismissed successfully"
                return 0
            fi

            # Fallback: Try keyboard navigation
            echo "Mouse click may have failed, trying keyboard navigation..."
            DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || true
            sleep 0.3
            # Tab to checkbox, space to check, tab to button, enter to click
            DISPLAY=:1 xdotool key Tab space Tab Return 2>/dev/null || true
            sleep 1

            # Check again
            if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "License Agreement\|Kingsoft Office Software\|End User License"; then
                echo "EULA dialog dismissed via keyboard navigation"
                return 0
            fi
        else
            # No license dialog found
            echo "No EULA dialog found"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 1
    done

    echo "Warning: Could not dismiss EULA dialog after $max_attempts attempts"
    return 1
}

# Dismiss any WPS first-run dialogs or tips
# Call this after launching WPS for the first time
dismiss_wps_dialogs() {
    sleep 2

    # First try to dismiss EULA if present
    dismiss_wps_eula 5

    # Dismiss "System Check" dialog about fonts - this appears after EULA
    # The dialog has a "Close" button in the bottom right
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "System Check"; then
        echo "Dismissing System Check dialog..."
        # Try clicking the Close button (red X or Close button)
        # From screenshot, Close button is at bottom right of dialog
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 wmctrl -c "System Check" 2>/dev/null || true
        sleep 0.3
    fi

    # Dismiss "WPS Office" default office software dialog
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "WPS Office$"; then
        echo "Dismissing WPS Office default dialog..."
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 wmctrl -c "WPS Office" 2>/dev/null || true
        sleep 0.5
    fi

    # Then try pressing Escape multiple times to close any other dialogs
    xdotool key Escape 2>/dev/null || true
    sleep 0.3
    xdotool key Escape 2>/dev/null || true
    sleep 0.3
    # Also try clicking away any welcome screens
    xdotool key Return 2>/dev/null || true
    sleep 0.3
}

# Take a screenshot using scrot
# Args: $1 - output path (default: /tmp/screenshot.png)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Export these functions for use in other scripts
export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f focus_window
export -f get_wps_window_id
export -f safe_xdotool
export -f dismiss_wps_eula
export -f dismiss_wps_dialogs
export -f take_screenshot
