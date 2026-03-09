#!/bin/bash
# Shared utilities for VeraCrypt task setup and export scripts

# Wait for a window with specified title to appear
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

# Focus a window by ID
focus_window() {
    local window_id="$1"

    if DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || \
       DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null; then
        sleep 0.3
        echo "Window focused: $window_id"
        return 0
    fi

    echo "Failed to focus window: $window_id"
    return 1
}

# Get the VeraCrypt main window ID
get_veracrypt_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i 'VeraCrypt' | head -1 | awk '{print $1}'
}

# Kill VeraCrypt processes
kill_veracrypt() {
    echo "Killing VeraCrypt processes..."
    pkill -f "veracrypt" 2>/dev/null || true
    sleep 2
}

# Check if VeraCrypt is running
is_veracrypt_running() {
    pgrep -f "veracrypt" > /dev/null
    return $?
}

# Take screenshot using ImageMagick (more reliable than scrot)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Write JSON result with permission-safe pattern
write_result_json() {
    local result_path="$1"
    local json_content="$2"

    TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$TEMP_JSON"

    rm -f "$result_path" 2>/dev/null || sudo rm -f "$result_path" 2>/dev/null || true
    cp "$TEMP_JSON" "$result_path" 2>/dev/null || sudo cp "$TEMP_JSON" "$result_path"
    chmod 666 "$result_path" 2>/dev/null || sudo chmod 666 "$result_path" 2>/dev/null || true
    rm -f "$TEMP_JSON"
}

# Export these functions
export -f wait_for_window
export -f wait_for_process
export -f focus_window
export -f get_veracrypt_window_id
export -f kill_veracrypt
export -f is_veracrypt_running
export -f take_screenshot
export -f write_result_json
