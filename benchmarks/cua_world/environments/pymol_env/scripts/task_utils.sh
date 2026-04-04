#!/bin/bash
# Shared utilities for PyMOL environment tasks

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Get PyMOL window ID
get_pymol_window_id() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "pymol" | head -1 | awk '{print $1}'
}

# Check if PyMOL is running
is_pymol_running() {
    pgrep -f "/usr/bin/pymol" > /dev/null 2>&1 || pgrep -f "pymol" > /dev/null 2>&1
}

# Wait for PyMOL window to appear
wait_for_pymol() {
    local timeout="${1:-60}"
    local elapsed=0
    echo "Waiting for PyMOL window (timeout: ${timeout}s)..." >&2
    while [ $elapsed -lt $timeout ]; do
        WID=$(get_pymol_window_id)
        if [ -n "$WID" ]; then
            echo "PyMOL window found: ${WID}" >&2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: PyMOL window not found after ${timeout}s" >&2
    return 1
}

# Focus PyMOL window
focus_pymol() {
    local WID=$(get_pymol_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$WID" 2>/dev/null
        return 0
    fi
    return 1
}

# Maximize PyMOL window
maximize_pymol() {
    local WID=$(get_pymol_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null
        return 0
    fi
    return 1
}

# Kill any running PyMOL instances
kill_pymol() {
    pkill -f "pymol" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    pkill -9 -f "pymol" 2>/dev/null || true
    sleep 1
}

# Launch PyMOL with optional arguments
launch_pymol() {
    local args="$@"
    kill_pymol
    DISPLAY=:1 xhost +local: 2>/dev/null || true
    su - ga -c "DISPLAY=:1 QT_QPA_PLATFORM=xcb setsid pymol -q ${args} > /tmp/pymol_launch.log 2>&1 &"
    wait_for_pymol 60
}

# Launch PyMOL with a specific PDB file
launch_pymol_with_file() {
    local pdb_file="$1"
    if [ ! -f "$pdb_file" ]; then
        echo "ERROR: PDB file not found: ${pdb_file}" >&2
        return 1
    fi
    launch_pymol "$pdb_file"
    sleep 3
    maximize_pymol
    sleep 1
}
