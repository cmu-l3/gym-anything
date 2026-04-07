#!/bin/bash
# Shared utilities for Activity Browser environment tasks

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
export PATH="/opt/miniconda3/bin:$PATH"

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Get Activity Browser window ID
get_ab_window_id() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | \
        grep -i -E "activity.browser|brightway|Activity Browser" | head -1 | awk '{print $1}'
}

# Check if Activity Browser is running
is_ab_running() {
    pgrep -f "activity-browser" > /dev/null 2>&1 || \
    pgrep -f "activity_browser" > /dev/null 2>&1
}

# Wait for Activity Browser window to appear
wait_for_ab() {
    local timeout="${1:-60}"
    local elapsed=0
    echo "Waiting for Activity Browser window (timeout: ${timeout}s)..." >&2
    while [ $elapsed -lt $timeout ]; do
        WID=$(get_ab_window_id)
        if [ -n "$WID" ]; then
            echo "Activity Browser window found: ${WID}" >&2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Activity Browser window not found after ${timeout}s" >&2
    return 1
}

# Focus Activity Browser window
focus_ab() {
    local WID=$(get_ab_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$WID" 2>/dev/null
        return 0
    fi
    return 1
}

# Maximize Activity Browser window
maximize_ab() {
    local WID=$(get_ab_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null
        return 0
    fi
    return 1
}

# Kill any running Activity Browser instances
kill_ab() {
    pkill -f "activity-browser" 2>/dev/null || true
    pkill -f "activity_browser" 2>/dev/null || true
    sleep 2
    pkill -9 -f "activity-browser" 2>/dev/null || true
    pkill -9 -f "activity_browser" 2>/dev/null || true
    sleep 1
}

# Ensure default is the active Brightway2 project
set_project() {
    su - ga -c "export PATH='/opt/miniconda3/bin:\$PATH' && export LD_LIBRARY_PATH='/opt/miniconda3/envs/ab/lib:\$LD_LIBRARY_PATH' && /opt/miniconda3/envs/ab/bin/python -c \"
import brightway2 as bw
bw.projects.set_current('default')
print('Active project:', bw.projects.current)
\"" 2>&1 || echo "WARNING: Failed to set project" >&2
}

# Launch Activity Browser
launch_ab() {
    kill_ab
    # Ensure correct project is active before launching
    set_project
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xhost +local: 2>/dev/null || true
    su - ga -c "setsid /usr/local/bin/launch-activity-browser > /tmp/ab_launch.log 2>&1 &"
    wait_for_ab 60
    sleep 3
    maximize_ab
    sleep 1
}
