#!/bin/bash
# Shared utilities for LibreOffice Impress task setup and export scripts
# NOTE: Do NOT use set -euo pipefail in this file - it is sourced by other scripts

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 60)
# Returns: 0 if found, 1 if timeout
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-60}
    local start=$(date +%s)

    echo "Waiting for window matching '$window_pattern'..."

    while true; do
        local elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timeout: Window not found after ${timeout}s"
            return 1
        fi
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
    done
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

    while true; do
        local elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timeout: File not ready: $filepath"
            return 1
        fi
        if [ -f "$filepath" ]; then
            echo "File ready: $filepath"
            return 0
        fi
        sleep 0.5
    done
}

# Wait for a process to start
# Args: $1 - process name pattern (pgrep pattern)
#       $2 - timeout in seconds (default: 30)
# Returns: 0 if process found, 1 if timeout
wait_for_process() {
    local process_pattern="$1"
    local timeout=${2:-30}
    local start=$(date +%s)

    echo "Waiting for process matching '$process_pattern'..."

    while true; do
        local elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timeout: Process not found after ${timeout}s"
            return 1
        fi
        if pgrep -fc "$process_pattern" > /dev/null 2>&1; then
            echo "Process found after ${elapsed}s"
            return 0
        fi
        sleep 1
    done
}

# Focus a window by name pattern
# Args: $1 - window name pattern
# Returns: 0 if focused successfully, 1 otherwise
focus_window() {
    local pattern="$1"
    DISPLAY=:1 wmctrl -a "$pattern" 2>/dev/null && return 0

    # Try by window ID
    local wid
    wid=$(DISPLAY=:1 wmctrl -l | grep -i "$pattern" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null && return 0
    fi

    echo "Warning: Failed to focus window: $pattern"
    return 1
}

# Maximize a window by name pattern
# Args: $1 - window name pattern
maximize_window() {
    local pattern="$1"
    DISPLAY=:1 wmctrl -r "$pattern" -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

# Get the window ID for LibreOffice Impress
# Returns: window ID or empty string
get_impress_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'impress\|\.odp\|\.pptx' | head -1 | awk '{print $1}'
}

# Kill all LibreOffice processes
kill_libreoffice() {
    pkill -f "soffice" 2>/dev/null || true
    sleep 1
    pkill -9 -f "soffice" 2>/dev/null || true
    sleep 1
}

# Run xdotool command as specified user with DISPLAY set
# Args: $1 - user (e.g., "ga")
#       $2 - display (e.g., ":1")
#       rest - xdotool arguments
safe_xdotool() {
    local user="$1"
    local display="$2"
    shift 2
    su - "$user" -c "DISPLAY=$display xdotool $*" 2>/dev/null || true
}

# Dismiss all LibreOffice startup dialogs (Recovery, Template, What's New)
dismiss_dialogs() {
    for attempt in 1 2 3; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Recovery\|Template\|What"; then
            echo "Dismissing dialog (attempt $attempt)..."
            su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
            sleep 2
        else
            break
        fi
    done
    # Extra Escape to dismiss any remaining popups/infobars
    su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
    sleep 1
}
