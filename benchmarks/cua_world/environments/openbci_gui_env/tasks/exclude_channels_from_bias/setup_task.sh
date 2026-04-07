#!/bin/bash
set -e
echo "=== Setting up exclude_channels_from_bias task ==="

# Source shared utilities if available, otherwise define basics
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    echo "Warning: openbci_task_utils.sh not found, defining local helpers"
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/bias_config.png
rm -f /tmp/task_result.json

# Ensure OpenBCI GUI is running and at the start screen
# We kill any existing instance to ensure a fresh state at the System Control Panel
echo "Ensuring fresh OpenBCI GUI instance..."
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch the app
# Using the installed wrapper or direct path
if [ -f "/home/ga/launch_openbci.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_openbci.sh &"
else
    su - ga -c "DISPLAY=:1 /usr/local/bin/openbci_gui &"
fi

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window for consistent coordinate space and visibility
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Capture initial state
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="