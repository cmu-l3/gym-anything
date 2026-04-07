#!/bin/bash
set -e

echo "=== Setting up fillet_arc_profile task ==="

# Source utility functions if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace
rm -f /home/ga/Documents/SolveSpace/fillet_profile.slvs

# Kill any running SolveSpace instances
pkill -f solvespace 2>/dev/null || true
sleep 1
pkill -9 -f solvespace 2>/dev/null || true

# Launch SolveSpace with a new empty sketch
echo "Launching SolveSpace..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority solvespace > /tmp/solvespace_task.log 2>&1 &"
sleep 5

# Wait for SolveSpace window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "solvespace"; then
        echo "SolveSpace window found"
        break
    fi
    sleep 1
done

# Maximize the canvas window and move property browser to the side
CANVAS_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'solvespace' | grep -iv 'property browser' | awk '{print $1}' | head -1)
if [ -n "$CANVAS_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$CANVAS_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
else
    DISPLAY=:1 wmctrl -r "SolveSpace" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 0.5
DISPLAY=:1 wmctrl -r "Property Browser" -e 0,1538,64,382,370 2>/dev/null || true

# Dismiss any popup dialogs
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 0.5

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== fillet_arc_profile task setup complete ==="