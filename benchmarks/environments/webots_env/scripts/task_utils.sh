#!/bin/bash
# Shared utilities for Webots tasks

# Detect WEBOTS_HOME
detect_webots_home() {
    if [ -d /usr/local/webots ]; then
        echo "/usr/local/webots"
    elif [ -d /usr/share/webots ]; then
        echo "/usr/share/webots"
    else
        echo ""
    fi
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Check if Webots is running
is_webots_running() {
    pgrep -f "webots" > /dev/null 2>&1
}

# Get Webots window ID
get_webots_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "webots" | head -1 | awk '{print $1}'
}

# Focus and maximize Webots window
focus_webots() {
    local WID
    WID=$(get_webots_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        return 0
    fi
    return 1
}

# Wait for Webots window to appear
wait_for_webots_window() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "webots"; then
            echo "Webots window detected"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Webots window not detected after ${timeout}s"
    return 1
}

# Launch Webots with a world file
launch_webots_with_world() {
    local world_file="$1"
    local WEBOTS_HOME
    WEBOTS_HOME=$(detect_webots_home)

    if [ -z "$WEBOTS_HOME" ]; then
        echo "ERROR: Cannot find Webots installation"
        return 1
    fi

    # Kill any existing Webots instances
    pkill -f "webots" 2>/dev/null || true
    sleep 2

    if [ -n "$world_file" ] && [ -f "$world_file" ]; then
        su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 WEBOTS_HOME=$WEBOTS_HOME setsid $WEBOTS_HOME/webots --batch --mode=pause \"$world_file\" > /tmp/webots_task.log 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 WEBOTS_HOME=$WEBOTS_HOME setsid $WEBOTS_HOME/webots --batch --mode=pause > /tmp/webots_task.log 2>&1 &"
    fi

    # Wait for window to appear
    wait_for_webots_window 60
}

# Check if a world file is loaded (check window title)
check_world_loaded() {
    local world_name="$1"
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$world_name"
}

# Get window title
get_webots_window_title() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "webots" | head -1 | sed 's/^[^ ]* *[^ ]* *[^ ]* *//'
}

# Check if a file exists and has minimum size
check_file_exists() {
    local filepath="$1"
    local min_size="${2:-0}"
    if [ -f "$filepath" ]; then
        local size
        size=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
        if [ "$size" -ge "$min_size" ]; then
            return 0
        fi
    fi
    return 1
}

# Get file size in bytes
get_file_size() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        stat -c%s "$filepath" 2>/dev/null || echo 0
    else
        echo 0
    fi
}
