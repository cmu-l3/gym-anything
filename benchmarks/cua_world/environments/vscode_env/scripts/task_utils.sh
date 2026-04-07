#!/bin/bash
# Shared utilities for VSCode task setup and export scripts

# Wait for a window with specified title to appear
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_pattern'..."
    while [ $elapsed -lt $timeout ]; do
        if wmctrl -l | grep -qi "$window_pattern"; then
            echo "✅ Window found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    echo "❌ Timeout: Window not found after ${timeout}s"
    return 1
}

# Wait for a file to be created or modified
wait_for_file() {
    local filepath="$1"
    local timeout=${2:-10}
    local start=$(date +%s)

    echo "Waiting for file: $filepath"
    while [ $(($(date +%s) - start)) -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            if [ $(find "$filepath" -mmin -0.2 2>/dev/null | wc -l) -gt 0 ] || \
               [ $(($(date +%s) - start)) -lt 2 ]; then
                echo "✅ File ready: $filepath"
                return 0
            fi
        fi
        sleep 0.5
    done
    echo "⚠️ Timeout: File not updated: $filepath"
    return 1
}

# Wait for VSCode process
wait_for_vscode() {
    local timeout=${1:-20}
    local elapsed=0

    echo "Waiting for VSCode process..."
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
            echo "✅ VSCode process found after ${elapsed}s"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    echo "❌ Timeout: VSCode process not found after ${timeout}s"
    return 1
}

# Focus VSCode window
focus_vscode_window() {
    local window_id=$(wmctrl -l | grep -i 'Visual Studio Code' | awk '{print $1; exit}')
    if [ -n "$window_id" ]; then
        wmctrl -ia "$window_id" 2>/dev/null || wmctrl -a "Visual Studio Code" 2>/dev/null
        sleep 0.3
        echo "✅ VSCode window focused"
        return 0
    fi
    echo "⚠️ VSCode window not found"
    return 1
}

# Safe xdotool command
safe_xdotool() {
    local user="$1"
    local display="$2"
    shift 2
    su - "$user" -c "DISPLAY=$display xdotool $*" 2>&1 | grep -v "^$"
    return ${PIPESTATUS[0]}
}

# Kill VSCode
kill_vscode() {
    pkill -u ga -f 'code.*--ms-enable-electron' 2>/dev/null || \
    pkill -u ga -f 'code' 2>/dev/null || true
    sleep 1
}

# Get VSCode window ID
get_vscode_window_id() {
    wmctrl -l 2>/dev/null | grep -i 'Visual Studio Code\|Code' | awk '{print $1; exit}'
}

# Take a screenshot
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"
    [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
}

# Export these functions
export -f wait_for_window
export -f wait_for_file
export -f wait_for_vscode
export -f focus_vscode_window
export -f safe_xdotool
export -f kill_vscode
export -f get_vscode_window_id
export -f take_screenshot
