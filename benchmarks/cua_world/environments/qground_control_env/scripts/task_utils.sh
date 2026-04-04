#!/bin/bash
# Shared utilities for QGroundControl tasks

ARDUPILOT_DIR="/opt/ardupilot"
QGC_APPIMAGE="/opt/QGroundControl-x86_64.AppImage"

take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
}

is_qgc_running() {
    pgrep -f "QGroundControl" > /dev/null 2>&1
}

is_sitl_running() {
    pgrep -f "/opt/ardupilot/build/sitl/bin/arducopter" > /dev/null 2>&1
}

focus_qgc() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "QGroundControl" 2>/dev/null || true
}

maximize_qgc() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "QGroundControl" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_qgc
}

ensure_sitl_running() {
    if ! is_sitl_running; then
        echo "SITL not running, starting..."
        su - ga -c "bash /home/ga/start_sitl.sh"
        local timeout=60
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if is_sitl_running; then
                echo "SITL started"
                sleep 10
                return 0
            fi
            sleep 3
            elapsed=$((elapsed + 3))
        done
        echo "WARNING: SITL may not have started"
        return 1
    fi
    return 0
}

ensure_qgc_running() {
    if ! is_qgc_running; then
        echo "QGC not running, starting..."
        su - ga -c "bash /home/ga/start_qgc.sh"
        local timeout=30
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if is_qgc_running; then
                echo "QGC started"
                sleep 5
                maximize_qgc
                return 0
            fi
            sleep 3
            elapsed=$((elapsed + 3))
        done
        echo "WARNING: QGC may not have started"
        return 1
    fi
    return 0
}

dismiss_dialogs() {
    # Click at known QGC dialog Ok button positions (1920x1080 coords)
    # Verified via visual grounding on maximized 1920x1080 window:
    # Dialog 1 (Serial permissions): Ok at (1262, 459)
    # Dialog 2 (Measurement Units): Ok at (1065, 383)
    # Dialog 3 (Vehicle Info): Ok at (1031, 444)
    # NOTE: Do NOT use Escape key - it triggers "Close QGroundControl" dialog
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1262 459 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1065 383 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1031 444 click 1 2>/dev/null || true
    sleep 0.5
}
