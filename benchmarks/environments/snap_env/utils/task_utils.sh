#!/bin/bash
# Shared utilities for all SNAP tasks

# Wait for a window matching a pattern to appear
# Usage: wait_for_window "SNAP" 30
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "WARNING: Window '$pattern' did not appear within ${timeout}s"
    return 1
}

# Wait for a file to exist
# Usage: wait_for_file "/path/to/file" 10
wait_for_file() {
    local filepath="$1"
    local timeout="${2:-10}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if [ -f "$filepath" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Wait for a process matching a pattern to start
# Usage: wait_for_process "snap" 20
wait_for_process() {
    local pattern="$1"
    local timeout="${2:-20}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if pgrep -f "$pattern" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Focus a window by name pattern
# Usage: focus_window "SNAP"
focus_window() {
    local pattern="$1"
    local wid
    wid=$(DISPLAY=:1 wmctrl -l | grep -i "$pattern" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null || true
        return 0
    fi
    return 1
}

# Get SNAP window ID
get_snap_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "SNAP" | head -1 | awk '{print $1}'
}

# Kill SNAP processes for a user (use /opt/snap to avoid matching Ubuntu snapd)
# Usage: kill_snap ga
kill_snap() {
    local user="${1:-ga}"
    pkill -u "$user" -f "/opt/snap/jre/bin/java" 2>/dev/null || true
    pkill -u "$user" -f "org.esa.snap" 2>/dev/null || true
    pkill -u "$user" -f "nbexec.*snap" 2>/dev/null || true
}

# Check if SNAP is running (use /opt/snap to avoid matching Ubuntu snapd)
is_snap_running() {
    pgrep -f "/opt/snap/jre/bin/java" > /dev/null 2>&1 || \
    pgrep -f "org.esa.snap" > /dev/null 2>&1 || \
    pgrep -f "nbexec.*snap" > /dev/null 2>&1
}

# Take a screenshot
# Usage: take_screenshot /tmp/screenshot.png
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Launch SNAP with optional file argument
# Usage: launch_snap [file_path]
launch_snap() {
    local file_arg="${1:-}"

    # Write a launcher script to avoid quoting issues with su -c
    cat > /tmp/launch_snap_now.sh << SNAPEOF
#!/bin/bash
export DISPLAY=:1
export _JAVA_AWT_WM_NONREPARENTING=1
/opt/snap/bin/snap --nosplash ${file_arg} > /tmp/snap_task.log 2>&1 &
SNAPEOF
    chmod +x /tmp/launch_snap_now.sh
    su - ga -c "bash /tmp/launch_snap_now.sh"
}

# Wait for SNAP to fully start (process + window)
# Usage: wait_for_snap_ready 120
wait_for_snap_ready() {
    local timeout="${1:-120}"
    local elapsed=0

    echo "Waiting for SNAP process..."
    while [ $elapsed -lt $timeout ]; do
        if is_snap_running; then
            echo "SNAP process detected after ${elapsed}s"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if ! is_snap_running; then
        echo "ERROR: SNAP process did not start within ${timeout}s"
        return 1
    fi

    echo "Waiting for SNAP window..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "SNAP"; then
            echo "SNAP window appeared after ${elapsed}s"
            sleep 5  # Extra time for full UI initialization
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "ERROR: SNAP window did not appear within ${timeout}s"
    return 1
}

# Dismiss common SNAP startup dialogs
# The "SNAP Update" dialog appears when SNAP checks for plugin updates
dismiss_snap_dialogs() {
    echo "Checking for SNAP startup dialogs..."
    sleep 5

    # Check if an update dialog is present by looking for the dialog window
    # Click "Remember my decision" checkbox (491,379 in 1280x720 -> 737,569 in 1920x1080)
    DISPLAY=:1 xdotool mousemove 737 569 click 1 2>/dev/null || true
    sleep 1
    # Click "No" button (754,403 in 1280x720 -> 1131,605 in 1920x1080)
    DISPLAY=:1 xdotool mousemove 1131 605 click 1 2>/dev/null || true
    sleep 2

    # Press Escape for any other unexpected dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
}

export -f wait_for_window
export -f wait_for_file
export -f wait_for_process
export -f focus_window
export -f get_snap_window_id
export -f kill_snap
export -f is_snap_running
export -f take_screenshot
export -f launch_snap
export -f wait_for_snap_ready
export -f dismiss_snap_dialogs
