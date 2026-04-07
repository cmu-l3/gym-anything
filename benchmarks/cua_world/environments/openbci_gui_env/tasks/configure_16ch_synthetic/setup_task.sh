#!/bin/bash
set -e
echo "=== Setting up Configure 16-Channel Synthetic Task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Kill any existing OpenBCI instances
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI
# We use the user's launch script to ensure environment variables are correct
echo "Launching OpenBCI GUI..."
su - ga -c "setsid /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear using wmctrl
echo "Waiting for OpenBCI GUI window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI" > /dev/null; then
        echo "OpenBCI GUI window detected"
        break
    fi
    sleep 1
done

# Give it a few seconds to fully render the System Control Panel
sleep 5

# Maximize the window to ensure all controls are visible
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Clean up previous screenshots or results
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/16ch_synthetic_session.png
rm -f /tmp/task_result.json

# Take initial screenshot of the System Control Panel
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "OpenBCI GUI should be at the System Control Panel."