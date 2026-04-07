#!/bin/bash
set -e
echo "=== Setting up Ganglion 4ch Synthetic Task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ensure directories exist
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"

# Cleanup previous artifacts to prevent false positives
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/ganglion_4ch_display.png
rm -f /tmp/task_result.json

# Kill any existing OpenBCI GUI instance
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2
pkill -9 -f "OpenBCI_GUI" 2>/dev/null || true
sleep 1

# Launch OpenBCI GUI
# We use the standard launcher which opens the System Control Panel by default
echo "Launching OpenBCI GUI..."
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; \
    setsid bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
GUI_STARTED=0
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci"; then
        echo "Window detected."
        GUI_STARTED=1
        break
    fi
    sleep 1
done

if [ "$GUI_STARTED" -eq 0 ]; then
    echo "ERROR: OpenBCI GUI failed to start."
    exit 1
fi

# Wait a moment for the UI to render
sleep 5

# Maximize the window for better agent visibility
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "OpenBCI GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "GUI should be at System Control Panel (default start screen)."