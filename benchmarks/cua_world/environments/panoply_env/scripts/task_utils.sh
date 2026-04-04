#!/bin/bash
# Shared utilities for Panoply tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Check if Panoply is running
is_panoply_running() {
    if pgrep -f "Panoply.jar" > /dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

# Wait for Panoply window to appear
wait_for_panoply() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "panoply"; then
            echo "Panoply window detected after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Panoply window not detected within ${timeout}s" >&2
    return 1
}

# Focus Panoply window
focus_panoply() {
    DISPLAY=:1 wmctrl -a "Panoply" 2>/dev/null || \
    DISPLAY=:1 wmctrl -a "panoply" 2>/dev/null || true
}

# Maximize Panoply window
maximize_panoply() {
    local window_id
    window_id=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "panoply" | awk '{print $1}' | head -1)
    if [ -n "$window_id" ]; then
        DISPLAY=:1 wmctrl -i -r "$window_id" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# Get Panoply window info
get_panoply_window() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "panoply" | head -1
}

# Safe xdotool command
safe_xdotool() {
    DISPLAY=:1 xdotool "$@" 2>/dev/null || true
}

# Wait for a file to appear
wait_for_file() {
    local filepath="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            echo "File found: $filepath" >&2
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "File not found within ${timeout}s: $filepath" >&2
    return 1
}
