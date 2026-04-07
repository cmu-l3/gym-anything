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

# Kill all OpenICE-related processes
kill_openice() {
    pkill -f "java.*demo-apps" 2>/dev/null || true
    pkill -f "gradlew.*demo-apps" 2>/dev/null || true
    pkill -f "GradleWrapperMain" 2>/dev/null || true
    pkill -f "launch_supervisor" 2>/dev/null || true
    sleep 3
    # Force kill any remaining
    pkill -9 -f "java.*demo-apps" 2>/dev/null || true
    pkill -9 -f "gradlew.*demo-apps" 2>/dev/null || true
    # Clean up Gradle lock files
    rm -f /home/ga/.gradle/wrapper/dists/*.lock 2>/dev/null || true
    rm -f /opt/openice/mdpnp/.gradle/*.lock 2>/dev/null || true
    sleep 2
}

# Launch OpenICE and wait for window
launch_and_wait_for_openice() {
    echo "Launching OpenICE..."
    su - ga -c "cd /home/ga/openice && DISPLAY=:1 nohup ./launch_supervisor.sh > /dev/null 2>&1" &
    # Wait for process to appear
    sleep 30
    # Then wait for window
    if wait_for_window "openice|ice|supervisor|demo" 180; then
        echo "OpenICE window detected!"
        return 0
    fi
    echo "OpenICE window not detected after launch attempt"
    return 1
}

# Start OpenICE if not running, and ensure the window is visible
ensure_openice_running() {
    local window_pattern="openice|ice|supervisor|demo"

    # Check if window is already visible
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "$window_pattern" > /dev/null 2>&1; then
        echo "OpenICE window already visible"
        return 0
    fi

    # Window not visible - check if process is running (stale process without GUI)
    if is_openice_running; then
        echo "OpenICE process running but no window, waiting for window..."
        if wait_for_window "$window_pattern" 90; then
            echo "OpenICE window appeared"
            return 0
        fi
        echo "Window still missing after 90s, killing stale processes..."
        kill_openice
    fi

    # Attempt 1: Launch fresh
    if launch_and_wait_for_openice; then
        return 0
    fi

    # Attempt 2: Kill everything and try one more time
    echo "First launch attempt failed, retrying..."
    kill_openice
    if launch_and_wait_for_openice; then
        return 0
    fi

    echo "WARNING: Could not get OpenICE window after 2 attempts"
    return 1
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
