#!/bin/bash
echo "=== Setting up open_and_run_simulation task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instance
pkill -f "webots" 2>/dev/null || true
sleep 3

# Launch Webots without any world file (empty/welcome state)
# Use --batch to suppress dialogs and --mode=pause to start paused
su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 WEBOTS_HOME=$WEBOTS_HOME setsid $WEBOTS_HOME/webots --batch --mode=pause > /tmp/webots_task.log 2>&1 &"

# Wait for Webots window to appear
wait_for_webots_window 90

sleep 5

# Focus and maximize the window
focus_webots

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Webots is open with no world loaded."
echo "Agent should: File > Open Sample World > demos > soccer.wbt, then click Play"
