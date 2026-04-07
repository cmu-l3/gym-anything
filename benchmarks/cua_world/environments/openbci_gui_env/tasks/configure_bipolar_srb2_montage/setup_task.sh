#!/bin/bash
set -e
echo "=== Setting up SRB2 Configuration Task ==="

# Source OpenBCI utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f "OpenBCI_GUI" 2>/dev/null || true
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/srb2_config.png 2>/dev/null || true

# Launch OpenBCI GUI
# We use a helper script if available, or direct launch
if [ -f "/home/ga/launch_openbci.sh" ]; then
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /dev/null 2>&1 &"
else
    # Fallback to direct executable find
    OPENBCI_EXEC=$(find /opt/openbci_gui -name "OpenBCI_GUI" -type f | head -1)
    DIR=$(dirname "$OPENBCI_EXEC")
    su - ga -c "cd $DIR && export DISPLAY=:1 && setsid $OPENBCI_EXEC > /dev/null 2>&1 &"
fi

# Wait for window
echo "Waiting for OpenBCI GUI..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
        echo "OpenBCI GUI detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Start Synthetic Session Automagically
# The task description says "Starting from a live Synthetic session"
# We need to simulate the user clicking "Synthetic" -> "Start Session" or use a startup flag if available.
# Since OpenBCI GUI doesn't have CLI flags for auto-start, we rely on the agent or use xdotool to prep it.
# However, to be robust and follow "Initial State Requirements", we should try to get it to the live state.
#
# Heuristic: Click "Synthetic" (left panel) then "Start Session" (top left)
# Coordinates depend on resolution (1920x1080).
# Control Panel "Synthetic" button approx: 330, 450 (varies by version)
# "Start Session" button approx: 330, 800
#
# NOTE: To reduce fragility, we will let the agent start the session if xdotool fails,
# BUT the task description implies it starts running. Let's try to set it up.

echo "Attempting to start synthetic session..."
sleep 5 # Wait for splash screen
# Click Synthetic (approximate location on 1080p)
DISPLAY=:1 xdotool mousemove 330 450 click 1
sleep 1
# Click Start Session
DISPLAY=:1 xdotool mousemove 330 800 click 1
sleep 5

# Ensure hardware settings are CLOSED (default state)
# (No action needed, defaults to closed)

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="