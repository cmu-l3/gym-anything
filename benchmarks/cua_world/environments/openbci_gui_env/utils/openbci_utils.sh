#!/bin/bash
# Shared utilities for OpenBCI GUI task setup scripts.
# Source this file from setup_task.sh scripts.
# NOTE: Do NOT use set -euo pipefail in scripts that source this file.

OPENBCI_EXEC_PATH=$(cat /opt/openbci_exec_path.txt 2>/dev/null || echo "")
OPENBCI_BASE_DIR=$(cat /opt/openbci_base_dir.txt 2>/dev/null || echo "")

# Kill any running OpenBCI GUI instances and wait for window to close
kill_openbci() {
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    sleep 2
    pkill -9 -f "OpenBCI_GUI" 2>/dev/null || true
    # Wait for window to disappear (up to 8s)
    for i in $(seq 1 8); do
        if ! DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
             grep -qi "openbci"; then
            break
        fi
        sleep 1
    done
    sleep 1
}

# Launch OpenBCI GUI and wait for it to be fully interactive
launch_openbci() {
    kill_openbci
    # Clear stale log to avoid false positive detection
    rm -f /tmp/openbci_task.log 2>/dev/null || true
    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; \
        bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"

    echo "Waiting for OpenBCI GUI to be fully loaded..."
    local timeout=${1:-90}
    local setup_complete=0
    for i in $(seq 1 $timeout); do
        # Wait for the LAST startup message ("not being run with Administrator access").
        # This appears after "Setup is complete!" and confirms the Control Panel is
        # fully initialized and interactive. Earlier signals ("TopNav: Internet Connection",
        # "Setup is complete!") are NOT sufficient for reliable interactive clicks.
        if grep -q "not being run with Administrator access" /tmp/openbci_task.log 2>/dev/null; then
            echo "OpenBCI GUI fully loaded after ${i}s"
            setup_complete=1
            break
        fi
        sleep 1
    done

    if [ "$setup_complete" -eq 0 ]; then
        # Fallback: accept if "Setup is complete!" appeared
        if grep -q "Setup: Setup is complete!" /tmp/openbci_task.log 2>/dev/null; then
            echo "WARNING: Administrator check did not appear but Setup is complete"
            setup_complete=1
        else
            echo "WARNING: OpenBCI GUI setup did not complete within ${timeout}s"
            tail -20 /tmp/openbci_task.log 2>/dev/null
            return 1
        fi
    fi

    sleep 5  # Settle time after setup - allow GUI to fully render widgets
    return 0
}

# Launch OpenBCI GUI and use xdotool to start a synthetic session automatically.
# This navigates the Control Panel and clicks Start Session, then starts data stream.
# Resolution is 1920x1080.
launch_openbci_synthetic() {
    launch_openbci

    echo "Starting synthetic session via xdotool..."

    # Find the OpenBCI window ID
    local WID
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
          xdotool search --name "OpenBCI" 2>/dev/null | tail -1)

    if [ -z "$WID" ]; then
        echo "WARNING: Could not find OpenBCI window ID"
        WID=""
    fi

    # Raise and focus the window (wmctrl works as root)
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        sleep 0.5
    fi

    # Click on SYNTHETIC option in the Control Panel.
    # CRITICAL: xdotool absolute-coordinate clicks do NOT work when run as root.
    # Must run xdotool as the ga user via "su - ga -c".
    # CRITICAL: Use semicolons within ONE su -ga -c call (mousemove; sleep; click)
    # for reliable behavior. Separate su -ga -c calls have a race condition where the
    # mouse position can change between calls. Combined "mousemove X Y click 1" also
    # has X11 sync issues in this context.
    # OpenBCI GUI Control Panel is on the left; data source list order:
    #   1. CYTON (live), 2. GANGLION (live), 3. PLAYBACK (from file),
    #   4. SYNTHETIC (algorithmic), 5. STREAMING (from external)
    # Coordinates empirically verified in 1920x1080 (inner window at 70,64, size 1024x768):
    #   SYNTHETIC text center: (180, 207) in 1920x1080 (y range 200-220)
    su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove --sync 180 207; sleep 0.1; xdotool click 1' 2>/dev/null || true
    sleep 1

    # Click START SESSION button (below the data source list)
    # Empirically verified coordinate: (200, 275) in 1920x1080
    # (inner window at 70,64, size 1024x768; START SESSION at window-relative ~130,211)
    su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove --sync 200 275; sleep 0.1; xdotool click 1' 2>/dev/null || true

    # Wait for session to initialize (check only the current run's log)
    echo "Waiting for session to start..."
    local session_started=0
    for i in $(seq 1 20); do
        if grep -q "\[SUCCESS\]: Session started!" /tmp/openbci_task.log 2>/dev/null; then
            echo "Session started after ${i}s"
            session_started=1
            break
        fi
        sleep 1
    done

    if [ "$session_started" -eq 0 ]; then
        echo "WARNING: Session start not confirmed in log, continuing..."
    fi

    sleep 2

    # Start data stream using SPACEBAR shortcut (run as ga user)
    su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool key space' 2>/dev/null || true

    sleep 3
    echo "Synthetic session with data stream started (best effort)"
}

# Take a window screenshot using xwd (works with GNOME compositor)
take_screenshot() {
    local output_path=${1:-/tmp/openbci_screenshot.png}
    local xwd_path="/tmp/openbci_screen.xwd"

    # Find the OpenBCI window (search by name since class "java" is unreliable)
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
          xdotool search --name "OpenBCI" 2>/dev/null | tail -1)

    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            xwd -id "$WID" -out "$xwd_path" 2>/dev/null && \
            convert "$xwd_path" "$output_path" 2>/dev/null
        rm -f "$xwd_path"
    fi

    # Fallback: use scrot
    if [ ! -f "$output_path" ] || [ ! -s "$output_path" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$output_path" 2>/dev/null || true
    fi

    if [ -f "$output_path" ] && [ -s "$output_path" ]; then
        echo "Screenshot saved: $output_path"
        return 0
    else
        echo "WARNING: Could not take screenshot"
        return 1
    fi
}

# Count screenshot files in the Screenshots/ subdirectory (OpenBCI saves as .jpg in Expert Mode)
count_screenshots() {
    find /home/ga/Documents/OpenBCI_GUI/Screenshots/ \( -name "OpenBCI-*.jpg" -o -name "OpenBCI-*.png" \) 2>/dev/null | wc -l
}

echo "openbci_utils.sh loaded: EXEC=$OPENBCI_EXEC_PATH"
