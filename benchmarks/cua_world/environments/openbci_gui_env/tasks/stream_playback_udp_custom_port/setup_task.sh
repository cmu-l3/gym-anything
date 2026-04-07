#!/bin/bash
set -e

echo "=== Setting up Stream Playback UDP Task ==="

# Source shared utilities
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    echo "WARNING: Task utils not found"
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Prepare the specific EEG recording file
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TARGET_FILE="${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"

# Locate the source file (from install or environment data)
SOURCE_FILE=""
if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt"
fi

if [ -n "$SOURCE_FILE" ]; then
    echo "Copying recording file from $SOURCE_FILE..."
    cp "$SOURCE_FILE" "$TARGET_FILE"
    chown ga:ga "$TARGET_FILE"
else
    echo "ERROR: Could not find source EEG file. Creating dummy file for fallback."
    # Create a dummy file so the task is technically possible to attempt, though data will look wrong
    echo "%OpenBCI Raw EEG Data" > "$TARGET_FILE"
    echo "%Sample Rate = 250.0 Hz" >> "$TARGET_FILE"
    chown ga:ga "$TARGET_FILE"
fi

# Kill any existing OpenBCI instance
pkill -f "OpenBCI_GUI" || true
sleep 1

# Launch OpenBCI GUI in background
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null 2>&1; then
        echo "OpenBCI GUI window detected"
        break
    fi
    sleep 1
done

# Focus and Maximize
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="