#!/bin/bash
# Shared utilities for OpenVSP tasks

# Find OpenVSP binary
get_openvsp_bin() {
    if [ -f /tmp/openvsp_bin_path ]; then
        cat /tmp/openvsp_bin_path
        return
    fi
    for candidate in /usr/local/bin/openvsp /usr/bin/vsp /usr/local/bin/vsp /opt/OpenVSP/vsp; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
    find /usr /opt -name "vsp" -type f -executable 2>/dev/null | head -1
}

OPENVSP_BIN=$(get_openvsp_bin)
MODELS_DIR="/home/ga/Documents/OpenVSP"
EXPORTS_DIR="/home/ga/Documents/OpenVSP/exports"

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Kill OpenVSP
kill_openvsp() {
    pkill -f "$OPENVSP_BIN" 2>/dev/null || true
    sleep 2
    pkill -9 -f "$OPENVSP_BIN" 2>/dev/null || true
    sleep 1
}

# Launch OpenVSP with optional file
launch_openvsp() {
    local file="$1"
    if [ -n "$file" ]; then
        su - ga -c "DISPLAY=:1 setsid $OPENVSP_BIN '$file' > /tmp/openvsp_task.log 2>&1 &"
    else
        su - ga -c "DISPLAY=:1 setsid $OPENVSP_BIN > /tmp/openvsp_task.log 2>&1 &"
    fi
}

# Wait for OpenVSP window to appear
# Window title format: "OpenVSP 3.X.X - MM/DD/YY     filename.vsp3"
wait_for_openvsp() {
    local timeout="${1:-60}"
    local elapsed=0
    local wid=""
    while [ $elapsed -lt $timeout ]; do
        wid=$(DISPLAY=:1 xdotool search --name "OpenVSP" 2>/dev/null | head -1)
        if [ -n "$wid" ]; then
            echo "$wid"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo ""
    return 1
}

# Focus and maximize OpenVSP window
focus_openvsp() {
    local wid=$(DISPLAY=:1 xdotool search --name "OpenVSP" 2>/dev/null | head -1)
    if [ -n "$wid" ]; then
        DISPLAY=:1 xdotool windowactivate "$wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "$wid"
    fi
}

# Dismiss dialogs
dismiss_dialogs() {
    local count="${1:-2}"
    for i in $(seq 1 $count); do
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    done
}

# Check if OpenVSP is running
is_openvsp_running() {
    pgrep -f "$OPENVSP_BIN" > /dev/null 2>&1
}

# Write result JSON safely
write_result_json() {
    local content="$1"
    local file="${2:-/tmp/task_result.json}"
    local temp=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$temp"
    rm -f "$file" 2>/dev/null || sudo rm -f "$file" 2>/dev/null || true
    cp "$temp" "$file" 2>/dev/null || sudo cp "$temp" "$file"
    chmod 666 "$file" 2>/dev/null || sudo chmod 666 "$file" 2>/dev/null || true
    rm -f "$temp"
}
