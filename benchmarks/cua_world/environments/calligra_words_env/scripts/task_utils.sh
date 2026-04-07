#!/bin/bash
# Shared utilities for Calligra Words task setup and export scripts

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
    local start=$(date +%s)

    echo "Waiting for window matching '$window_pattern'..."

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if wmctrl -l | grep -qi "$window_pattern"; then
            echo "Window found after $(($(date +%s) - start))s"
            return 0
        fi
        sleep 0.5
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
    local start=$(date +%s)

    echo "Waiting for process matching '$process_pattern'..."

    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if pgrep -f "$process_pattern" > /dev/null; then
            echo "Process found after $(($(date +%s) - start))s"
            return 0
        fi
        sleep 0.5
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

# Get the window ID for Calligra Words
# Returns: window ID or empty string
get_calligra_window_id() {
    wmctrl -l | grep -i 'Calligra Words\|calligrawords\|\.odt\|\.docx' | awk '{print $1; exit}'
}

# Safe xdotool command with display and user context
# Args: $1 - user (e.g., "ga")
#       $2 - display (e.g., ":1")
#       rest - xdotool arguments
safe_xdotool() {
    local user="$1"
    local display="$2"
    shift 2

    su - "$user" -c "DISPLAY=$display XAUTHORITY=/home/$user/.Xauthority xdotool $*" 2>&1 | grep -v "^$"
    return ${PIPESTATUS[0]}
}

# Cleanly terminate Calligra and fall back to a hard kill if needed.
kill_calligra_processes() {
    pkill -TERM -f calligrawords 2>/dev/null || true
    sleep 2
    pkill -KILL -f calligrawords 2>/dev/null || true
    rm -f /home/ga/Documents/.~lock.* 2>/dev/null || true
}

# Launch Calligra Words with a document and detach from the shell.
launch_calligra_document() {
    local document_path="$1"
    local log_path="${2:-/tmp/calligra_words_task.log}"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords \"$document_path\" > \"$log_path\" 2>&1 < /dev/null &"
}

# Take a screenshot
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
export -f get_calligra_window_id
export -f safe_xdotool
export -f kill_calligra_processes
export -f launch_calligra_document
export -f take_screenshot
