#!/bin/bash
set -e
echo "=== Setting up Configure Left Hemisphere Montage Task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/left_hemi_montage.png
rm -f /tmp/task_result.json

# 3. Ensure the Recordings directory exists and has the required data
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
DATA_FILE="OpenBCI-EEG-S001-MotorImagery.txt"
SOURCE_DATA="/opt/openbci_data/$DATA_FILE"

mkdir -p "$RECORDINGS_DIR"
mkdir -p "/home/ga/Documents/OpenBCI_GUI/Screenshots"

# Copy the real EEG data file if it's not already there
if [ ! -f "$RECORDINGS_DIR/$DATA_FILE" ]; then
    if [ -f "$SOURCE_DATA" ]; then
        echo "Copying $DATA_FILE from system data..."
        cp "$SOURCE_DATA" "$RECORDINGS_DIR/$DATA_FILE"
    elif [ -f "/workspace/data/$DATA_FILE" ]; then
        echo "Copying $DATA_FILE from workspace data..."
        cp "/workspace/data/$DATA_FILE" "$RECORDINGS_DIR/$DATA_FILE"
    else
        echo "WARNING: Real EEG data file not found. Creating a dummy file for structure."
        # Create a dummy file if real data is missing (fallback to prevent crash, though task requires real data)
        echo "%OpenBCI Raw EEG Data" > "$RECORDINGS_DIR/$DATA_FILE"
        echo "%Sample Rate = 250 Hz" >> "$RECORDINGS_DIR/$DATA_FILE"
        for i in {1..1000}; do echo "0,0,0,0,0,0,0,0"; done >> "$RECORDINGS_DIR/$DATA_FILE"
    fi
fi
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# 4. Launch OpenBCI GUI to the initial System Control Panel
# We kill any existing instance to ensure a clean start state
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# 5. Take initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="