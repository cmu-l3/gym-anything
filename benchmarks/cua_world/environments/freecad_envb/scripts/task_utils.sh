#!/bin/bash
# Shared utilities for FreeCAD tasks

# Take a screenshot of the current desktop
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Kill any running FreeCAD instance
kill_freecad() {
    pkill -f freecad 2>/dev/null || true
    sleep 2
}

# Launch FreeCAD with an optional file
# Usage: launch_freecad [/path/to/file.FCStd]
launch_freecad() {
    local file="${1:-}"
    if [ -n "$file" ]; then
        su - ga -c "DISPLAY=:1 freecad '$file' > /tmp/freecad_task.log 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"
    fi
}

# Wait for FreeCAD window to appear
wait_for_freecad() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "freecad\|FreeCAD"; then
            echo "FreeCAD window detected"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: FreeCAD window not detected after ${timeout}s"
    return 1
}

# Maximize FreeCAD window
maximize_freecad() {
    sleep 1
    DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
    DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
}
