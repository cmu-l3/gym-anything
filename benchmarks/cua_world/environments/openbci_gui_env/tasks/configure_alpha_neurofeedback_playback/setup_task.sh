#!/bin/bash
set -e
echo "=== Setting up Configure Alpha Neurofeedback Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# 1. Kill any existing OpenBCI instances to ensure a clean start at Control Panel
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 1

# 2. Prepare the Recording Data
# The task requires 'OpenBCI-EEG-S001-EyesOpen.txt' in ~/Documents/OpenBCI_GUI/Recordings/
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"

SOURCE_FILE=""
# Check common locations for the source file
if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt"
fi

if [ -n "$SOURCE_FILE" ]; then
    echo "Copying playback file from $SOURCE_FILE..."
    cp "$SOURCE_FILE" "$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"
    chown ga:ga "$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"
else
    echo "WARNING: Source EEG file not found! creating a dummy file for testing (verification may fail if data is required)."
    # Create a dummy header so the GUI might at least recognize it, though playback will be empty
    echo "%Board = OpenBCI_GUI\$BoardCytonSerial" > "$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"
    chown ga:ga "$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"
fi

# 3. Launch OpenBCI GUI
# We want the agent to start at the System Control Panel
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
        echo "OpenBCI GUI detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# 4. Capture Initial State
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="