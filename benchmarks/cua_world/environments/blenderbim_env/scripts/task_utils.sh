#!/bin/bash
# Shared utilities for BlenderBIM tasks

# ── Screenshot ────────────────────────────────────────────────────────────
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}

# ── Blender process management ────────────────────────────────────────────
is_blender_running() {
    local count
    count=$(pgrep -c -f "/opt/blender/blender" 2>/dev/null) || count=0
    [ "$count" -gt 0 ] && echo "true" || echo "false"
}

get_blender_window() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "blender" | head -1 | awk '{print $1}'
}

focus_blender() {
    local wid
    wid=$(get_blender_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$wid" 2>/dev/null
        return 0
    fi
    return 1
}

maximize_blender() {
    local wid
    wid=$(get_blender_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null
        return 0
    fi
    return 1
}

# ── Launch Blender with a file ────────────────────────────────────────────
launch_blender() {
    local file="$1"
    if [ "$(is_blender_running)" = "true" ]; then
        echo "Blender is already running"
        return 0
    fi

    if [ -n "$file" ] && [ -f "$file" ]; then
        su - ga -c "DISPLAY=:1 setsid /opt/blender/blender '$file' > /tmp/blender_task.log 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"
    fi

    # Wait for Blender window to appear
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local wid
        wid=$(get_blender_window)
        if [ -n "$wid" ]; then
            echo "Blender window appeared: $wid"
            sleep 2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Blender window not detected within ${timeout}s"
    return 1
}

# ── Kill Blender ──────────────────────────────────────────────────────────
kill_blender() {
    pkill -f "/opt/blender/blender" 2>/dev/null || true
    sleep 2
}

# ── Dismiss dialogs ──────────────────────────────────────────────────────
dismiss_blender_dialogs() {
    # Press Escape twice to dismiss splash/dialogs
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 0.5
}

# ── Query IFC file with ifcopenshell ──────────────────────────────────────
query_ifc_file() {
    local ifc_file="$1"
    local query="$2"

    /opt/blender/blender --background --python-expr "
import sys, json
try:
    sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')
    import ifcopenshell
    ifc = ifcopenshell.open('${ifc_file}')
    ${query}
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null
}

# ── List windows ──────────────────────────────────────────────────────────
list_windows() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null
}
