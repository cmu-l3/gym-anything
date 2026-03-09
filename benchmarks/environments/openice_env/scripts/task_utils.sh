#!/bin/bash
# Shared utilities for OpenICE tasks

# Set display
export DISPLAY=:1

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Check if OpenICE is running
is_openice_running() {
    if pgrep -f "java.*demo-apps" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Get OpenICE window ID
get_openice_window_id() {
    DISPLAY=:1 wmctrl -l | grep -iE "openice|ice|supervisor|demo" | head -1 | awk '{print $1}'
}

# Focus OpenICE window
focus_openice_window() {
    local win_id=$(get_openice_window_id)
    if [ -n "$win_id" ]; then
        DISPLAY=:1 wmctrl -i -a "$win_id" 2>/dev/null
        sleep 0.5
        return 0
    fi
    return 1
}

# List windows
list_windows() {
    DISPLAY=:1 wmctrl -l 2>/dev/null
}

# Click at coordinates
click_at() {
    local x=$1
    local y=$2
    DISPLAY=:1 xdotool mousemove "$x" "$y" click 1
}

# Type text
type_text() {
    local text="$1"
    DISPLAY=:1 xdotool type "$text"
}

# Press key
press_key() {
    local key="$1"
    DISPLAY=:1 xdotool key "$key"
}

# Wait for window with timeout
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "$pattern" > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Start OpenICE if not running
ensure_openice_running() {
    if ! is_openice_running; then
        echo "Starting OpenICE..."
        su - ga -c "cd /home/ga/openice && DISPLAY=:1 ./launch_supervisor.sh" &
        sleep 30
        if ! is_openice_running; then
            echo "Failed to start OpenICE"
            return 1
        fi
    fi
    return 0
}

# Safe JSON value escaping
escape_json_value() {
    local value="$1"
    echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g' | tr '\n' ' '
}

# Create result JSON safely
create_result_json() {
    local temp_file=$(mktemp /tmp/result.XXXXXX.json)
    cat > "$temp_file"

    # Move to final location with permission handling
    rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
    cp "$temp_file" /tmp/task_result.json 2>/dev/null || sudo cp "$temp_file" /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
    rm -f "$temp_file"
}

echo "OpenICE task utilities loaded"
