#!/bin/bash
# Shared utilities for SolveSpace environment tasks

# Take a screenshot and save to the given path
# Uses 'import -window root' which works with GNOME compositor
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    echo "WARNING: Screenshot failed"
}

# Kill all running SolveSpace instances
kill_solvespace() {
    pkill -f /usr/bin/solvespace 2>/dev/null || pkill -f solvespace 2>/dev/null || true
    sleep 2
    # Force kill if still running
    pkill -9 -f solvespace 2>/dev/null || true
    sleep 1
}

# Launch SolveSpace with optional file argument
# Usage: launch_solvespace [filepath]
launch_solvespace() {
    local filepath="${1:-}"
    if [ -n "$filepath" ]; then
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority solvespace \"$filepath\" > /tmp/solvespace_task.log 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority solvespace > /tmp/solvespace_task.log 2>&1 &"
    fi
}

# Wait for SolveSpace window to appear
# Usage: wait_for_solvespace [timeout_seconds]
wait_for_solvespace() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "solvespace"; then
            echo "SolveSpace window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "WARNING: SolveSpace window not found after ${timeout}s"
    return 1
}

# Maximize the SolveSpace canvas window and move Property Browser to right side
# SolveSpace opens two X11 windows: the canvas and a floating Property Browser.
# The canvas window title is "filename — SolveSpace" or "(new sketch) — SolveSpace".
# The Property Browser title is "Property Browser — SolveSpace".
# wmctrl -r matches the first window found, so we must exclude the Property Browser
# by using the canvas window ID directly.
maximize_solvespace() {
    local canvas_id
    canvas_id=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'solvespace' | grep -iv 'property browser' | awk '{print $1}' | head -1)
    if [ -n "$canvas_id" ]; then
        DISPLAY=:1 wmctrl -i -r "$canvas_id" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    else
        DISPLAY=:1 wmctrl -r "SolveSpace" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    sleep 0.5
    # Move Property Browser to right side so it doesn't cover the menu bar
    DISPLAY=:1 wmctrl -r "Property Browser" -e 0,1538,64,382,370 2>/dev/null || true
}

# Check if SolveSpace process is running
is_solvespace_running() {
    pgrep -f /usr/bin/solvespace > /dev/null 2>&1 || pgrep -f "solvespace" > /dev/null 2>&1
}
