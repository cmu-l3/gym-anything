#!/bin/bash
set -e
echo "=== Setting up stream_filtered_playback_lsl task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the Recordings directory exists
mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots

# Ensure the required playback file exists
TARGET_FILE="/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"
SOURCE_FILE=""

# Check potential locations for the source file
if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"
fi

if [ -n "$SOURCE_FILE" ]; then
    echo "Copying playback data from $SOURCE_FILE to $TARGET_FILE..."
    cp "$SOURCE_FILE" "$TARGET_FILE"
    chown ga:ga "$TARGET_FILE"
else
    echo "WARNING: Could not find source EEG file! creating a dummy file for interface testing."
    # Create a dummy file if real data is missing (prevents immediate task failure, though playback won't look right)
    echo "%OpenBCI Raw EEG Data" > "$TARGET_FILE"
    echo "Sample Index, EXG Channel 0, EXG Channel 1, EXG Channel 2, EXG Channel 3, EXG Channel 4, EXG Channel 5, EXG Channel 6, EXG Channel 7" >> "$TARGET_FILE"
    for i in {1..1000}; do echo "$i,0,0,0,0,0,0,0,0" >> "$TARGET_FILE"; done
    chown ga:ga "$TARGET_FILE"
fi

# Clean up previous screenshots
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/lsl_filtered_setup.png

# Launch OpenBCI GUI if not running
if ! pgrep -f "OpenBCI_GUI" > /dev/null; then
    echo "Launching OpenBCI GUI..."
    # Use the utility function if available, otherwise manual launch
    if type launch_openbci >/dev/null 2>&1; then
        launch_openbci
    else
        su - ga -c "setsid DISPLAY=:1 /home/ga/launch_openbci.sh > /tmp/openbci.log 2>&1 &"
        sleep 10
    fi
fi

# Wait for window
echo "Waiting for OpenBCI window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI" > /dev/null; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="