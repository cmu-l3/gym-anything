#!/bin/bash
# Shared utilities for all GNU Octave tasks
# Source this file from setup_task.sh scripts

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Take a screenshot using xwd (works reliably on GNOME compositor)
# scrot/import -window root produce black images on GNOME
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    local xwd_path="${path%.png}.xwd"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xwd -root -out "$xwd_path" 2>/dev/null || true
    convert "$xwd_path" "$path" 2>/dev/null || true
    rm -f "$xwd_path" 2>/dev/null || true
}

# Get Octave window ID
get_octave_window() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Octave" 2>/dev/null | head -1
}

# Focus the Octave window
focus_octave() {
    local wid
    wid=$(get_octave_window)
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowactivate "$wid" 2>/dev/null || true
    fi
}

# Maximize the Octave window
maximize_octave() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "Octave" -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

# Wait for Octave GUI window to appear
wait_for_octave() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local wid
        wid=$(get_octave_window)
        if [ -n "$wid" ]; then
            echo "Octave GUI window detected (WID=$wid)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Octave window not detected after ${timeout}s"
    return 1
}

# Check if Octave is running (use full path to avoid pgrep self-match)
is_octave_running() {
    local count
    count=$(pgrep -c -f /usr/bin/octave 2>/dev/null || echo 0)
    [ "$count" -gt 0 ]
}

# Kill all Octave instances
kill_octave() {
    pkill -f "octave --gui" 2>/dev/null || true
    sleep 2
    pkill -9 -f "octave --gui" 2>/dev/null || true
    sleep 1
}

# Launch Octave GUI as user ga with setsid (critical: prevents SIGHUP on hook exit)
launch_octave() {
    local logfile="${1:-/tmp/octave_task.log}"
    su - ga -c "DISPLAY=:1 setsid octave --gui > $logfile 2>&1 &"
}

# Dismiss potential dialogs (Escape, Enter)
dismiss_dialogs() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
    sleep 1
}

# Standard task setup routine:
# 1. Kill existing Octave
# 2. Launch fresh Octave
# 3. Wait for window
# 4. Dismiss dialogs
# 5. Maximize and focus
# 6. Take initial screenshot
setup_octave_task() {
    local task_name="${1:-unknown_task}"

    echo "--- Setting up Octave for task: $task_name ---"

    # Kill existing instances
    kill_octave

    # Create evidence directory
    mkdir -p /tmp/task_evidence

    # Launch Octave
    launch_octave "/tmp/octave_${task_name}.log"
    sleep 8

    # Wait for window
    wait_for_octave 60

    # Dismiss any dialogs
    sleep 2
    dismiss_dialogs

    # Maximize and focus
    maximize_octave
    sleep 1
    focus_octave
    sleep 1

    # Take initial state screenshot
    take_screenshot "/tmp/task_evidence/${task_name}_initial_state.png"

    echo "--- Octave task setup complete: $task_name ---"
}
