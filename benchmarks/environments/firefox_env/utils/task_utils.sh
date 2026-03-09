#!/bin/bash
# Shared utility functions for Firefox tasks

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
    DISPLAY=:1 wmctrl -l | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local window_id=$1
    if [ -n "$window_id" ]; then
        DISPLAY=:1 wmctrl -i -a "$window_id" 2>/dev/null
        sleep 0.5
    fi
}

# Take screenshot
take_screenshot() {
    local output_path=${1:-/tmp/screenshot.png}
    DISPLAY=:1 scrot "$output_path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$output_path" 2>/dev/null || true
}

# Get Firefox profile path
get_profile_path() {
    local username=${1:-ga}
    echo "/home/$username/.mozilla/firefox/default.profile"
}

# Check if places.sqlite exists and is accessible
check_places_db() {
    local username=${1:-ga}
    local places_db="/home/$username/.mozilla/firefox/default.profile/places.sqlite"
    if [ -f "$places_db" ]; then
        echo "$places_db"
        return 0
    else
        echo ""
        return 1
    fi
}

# Query Firefox database (handles lock issues)
query_firefox_db() {
    local db_path=$1
    local query=$2

    if [ ! -f "$db_path" ]; then
        echo ""
        return 1
    fi

    # Try direct query first, then copy if locked
    local result
    result=$(sqlite3 "$db_path" "$query" 2>/dev/null)
    if [ $? -ne 0 ]; then
        # Database might be locked, create a copy
        local temp_db="/tmp/firefox_db_copy_$$.sqlite"
        cp "$db_path" "$temp_db" 2>/dev/null
        result=$(sqlite3 "$temp_db" "$query" 2>/dev/null)
        rm -f "$temp_db"
    fi
    echo "$result"
}
