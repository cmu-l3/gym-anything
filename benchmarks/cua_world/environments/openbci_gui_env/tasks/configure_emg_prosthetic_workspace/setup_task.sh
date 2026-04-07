#!/bin/bash
set -e

echo "=== Setting up Configure EMG Prosthetic Workspace Task ==="

# Source OpenBCI task utilities if available, or define minimal needed
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    # Fallback minimal definitions
    function launch_openbci() {
        pkill -f "OpenBCI_GUI" || true
        su - ga -c "DISPLAY=:1 setsid bash /home/ga/launch_openbci.sh > /dev/null 2>&1 &"
        sleep 10
    }
    function take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Kill any existing OpenBCI instances to ensure clean start
echo "Stopping OpenBCI GUI..."
pkill -f "OpenBCI_GUI" || true
sleep 2

# 2. Clean up previous artifacts
TARGET_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/emg_workspace.png"
if [ -f "$TARGET_SCREENSHOT" ]; then
    echo "Removing previous target screenshot..."
    rm "$TARGET_SCREENSHOT"
fi

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenBCI GUI to the Control Panel (start screen)
echo "Launching OpenBCI GUI..."
launch_openbci

# Wait for window to ensure it's up
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI" > /dev/null; then
        echo "OpenBCI GUI window detected."
        break
    fi
    sleep 1
done

# 5. Maximize the window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Capture initial state
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="