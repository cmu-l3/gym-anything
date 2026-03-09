#!/bin/bash
# Shared utilities for Floreant POS tasks

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

FLOREANT_JAR="/opt/floreantpos/floreantpos.jar"
FLOREANT_PIN="1111"

# Kill any running Floreant POS instance
kill_floreant() {
    echo "Killing any running Floreant POS..."
    pkill -f "floreantpos.jar" 2>/dev/null || true
    sleep 2
    pkill -9 -f "floreantpos.jar" 2>/dev/null || true
    sleep 1
}

# Launch Floreant POS as user ga
# CRITICAL: Use the launcher script (which sets DISPLAY internally),
# not `setsid DISPLAY=:1 java` — setsid requires a real binary as first arg
launch_floreant() {
    echo "Launching Floreant POS..."
    su - ga -c "setsid /usr/local/bin/floreant-pos > /tmp/floreant_task.log 2>&1 &"
}

# Wait for Floreant window to appear (timeout in seconds)
wait_for_floreant_window() {
    local timeout=${1:-90}
    local elapsed=0
    echo "Waiting for Floreant window (timeout: ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Floreant" 2>/dev/null | head -1)
        if [ -n "$WID" ]; then
            echo "Floreant window found (WID: $WID)"
            return 0
        fi
        # If java died, report and stop waiting
        if ! pgrep -f "floreantpos.jar" > /dev/null 2>&1; then
            echo "WARNING: Java process not running"
            cat /tmp/floreant_task.log 2>/dev/null | tail -20
            break
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Timed out waiting for Floreant window"
    return 1
}

# Get Floreant window ID
get_floreant_wid() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Floreant" 2>/dev/null | head -1
}

# Focus the Floreant window
focus_floreant() {
    local wid=$(get_floreant_wid)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowraise "$wid" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus "$wid" 2>/dev/null || true
    fi
}

# NOTE: Floreant POS does NOT require login at startup.
# The main terminal screen (DINE IN, TAKE OUT, BACK OFFICE, etc.) appears directly.
# PIN 1111 is only needed when accessing Back Office (the task agent does this as part of the task).
# This function is kept for reference but should NOT be called from start_and_login().
login_floreant() {
    echo "NOTE: login_floreant() is a no-op — Floreant POS starts on main terminal screen without login."
    echo "      The task agent enters PIN 1111 when they click BACK OFFICE."
}

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/floreant_screen.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
    echo "Screenshot saved: $path"
}

# Start Floreant POS and show the main terminal screen (no login required at startup)
# After this, the task agent will see the main POS terminal with DINE IN, TAKE OUT, BACK OFFICE, etc.
# To access Back Office, the agent must: click BACK OFFICE → enter PIN 1111 → click OK
start_and_login() {
    kill_floreant
    sleep 1
    launch_floreant
    wait_for_floreant_window 60
    sleep 5  # extra wait for Java Swing UI to fully render

    # Maximize window
    local wid=$(get_floreant_wid)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Floreant" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
    fi

    # Focus window without clicking any button — click on the header status bar area
    # at top-center (~y=60) which is above all terminal buttons and is safe to click.
    # Avoid center (960,540) which can land on BACK OFFICE or other buttons.
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 960 60 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus $(get_floreant_wid) 2>/dev/null || true
    sleep 1

    echo "Floreant POS ready — main terminal screen displayed"
}
