#!/bin/bash
set -e
echo "=== Setting up Configure Custom Channel Filters task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source OpenBCI utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Ensure OpenBCI GUI is NOT running initially (clean slate)
pkill -f "OpenBCI_GUI" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true
sleep 2

# Ensure the recording file exists
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"
TARGET_FILE="$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"

# Copy from backup if missing (OpenBCI environment setup usually places it here)
if [ ! -f "$TARGET_FILE" ]; then
    echo "Restoring EEG recording file..."
    if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
        cp "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" "$TARGET_FILE"
    elif [ -f "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" ]; then
        cp "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" "$TARGET_FILE"
    elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
        cp "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" "$TARGET_FILE"
    else
        echo "WARNING: Could not find EEG source file!"
    fi
fi
chown ga:ga "$TARGET_FILE" 2>/dev/null || true

# Ensure screenshot directory exists
mkdir -p "/home/ga/Documents/OpenBCI_GUI/Screenshots"
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# Remove any previous result screenshot
rm -f "/home/ga/Documents/OpenBCI_GUI/Screenshots/custom_filters.png"

# Launch OpenBCI GUI to the hub
echo "Launching OpenBCI GUI..."
# Using the installed launcher
if [ -f "/home/ga/launch_openbci.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"
else
    # Fallback
    su - ga -c "DISPLAY=:1 openbci_gui > /tmp/openbci_launch.log 2>&1 &"
fi

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="