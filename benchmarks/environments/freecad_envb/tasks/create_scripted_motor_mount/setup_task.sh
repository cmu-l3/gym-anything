#!/bin/bash
set -e
echo "=== Setting up create_scripted_motor_mount task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous artifacts
rm -f /home/ga/Documents/FreeCAD/motor_mount_plate.FCStd
rm -f /tmp/freecad_task.log

# Ensure document directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD
# Redirect stdout/stderr to a log file we can scan later for Python commands
echo "Launching FreeCAD..."
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window
wait_for_freecad 60

# Maximize window
maximize_freecad

# Attempt to ensure Python console is visible via config (optional best effort)
# In a real scenario, the agent should do this, but we want to ensure a consistent start.
# Note: Changing config while running might not work, but FreeCAD usually reads user.cfg at start.
# We rely on the agent to open it if missing, as stated in description.

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="