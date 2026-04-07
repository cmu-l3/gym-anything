#!/bin/bash
set -euo pipefail

echo "=== Setting up cooperative testworld task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean slate: remove any pre-existing output files
rm -f /home/ga/Desktop/cooperative_push.wbt

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

# Launch Webots with NO world loaded (empty state)
echo "Launching Webots with empty state..."
su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 WEBOTS_HOME=$WEBOTS_HOME setsid $WEBOTS_HOME/webots --batch --mode=pause > /tmp/webots_task.log 2>&1 &"

# Wait for window to appear
wait_for_webots_window 60
sleep 5

# Focus and maximize the window
focus_webots
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot to prove empty starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent should build the cooperative pushing world from scratch."
echo "Output must be saved to: /home/ga/Desktop/cooperative_push.wbt"