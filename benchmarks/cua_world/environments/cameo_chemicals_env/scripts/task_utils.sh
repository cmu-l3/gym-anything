#!/bin/bash
# task_utils.sh - Shared utility functions for CAMEO Chemicals tasks

# Kill Firefox for a user
kill_firefox() {
    local username=${1:-ga}
    echo "Killing Firefox for user: $username"
    pkill -u "$username" -f firefox 2>/dev/null || true
    sleep 2
    pkill -9 -u "$username" -f firefox 2>/dev/null || true
    sleep 1
}

# Wait for a process to start
wait_for_process() {
    local process_name=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for $process_name process (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$process_name" > /dev/null; then
            echo "$process_name process found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for $process_name process"
    return 1
}

# Wait for a window to appear
wait_for_window() {
    local window_name=$1
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$window_name' (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "$window_name"; then
            echo "Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout waiting for window '$window_name'"
    return 1
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla|CAMEO" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local window_id=$1
    if [ -n "$window_id" ]; then
        DISPLAY=:1 wmctrl -i -a "$window_id" 2>/dev/null
        sleep 0.5
    fi
}

# Maximize Firefox window
maximize_firefox() {
    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null
        echo "Firefox window maximized: $wid"
    fi
}

# Take screenshot
take_screenshot() {
    local output_path=${1:-/tmp/screenshot.png}
    DISPLAY=:1 scrot "$output_path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$output_path" 2>/dev/null || true
}

# Launch Firefox and navigate to a URL
launch_firefox_to_url() {
    local url=${1:-"https://cameochemicals.noaa.gov/"}
    local username=${2:-ga}
    local timeout=${3:-45}

    echo "Launching Firefox to: $url"
    su - "$username" -c "DISPLAY=:1 firefox -P default --no-remote '$url' > /tmp/firefox.log 2>&1 &"

    # Wait for Firefox process
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if pgrep -u "$username" -f firefox > /dev/null; then
            echo "Firefox process started after ${elapsed}s"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Wait for Firefox window
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla|CAMEO"; then
            echo "Firefox window appeared after ${elapsed}s"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Let page load
    sleep 5

    # Maximize and focus
    maximize_firefox
}

# Record task start time
record_start_time() {
    date +%s > /tmp/task_start_time
    echo "Task start time recorded: $(cat /tmp/task_start_time)"
}
