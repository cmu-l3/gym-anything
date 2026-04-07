#!/bin/bash
set -e
echo "=== Setting up Configure Head Plot Widget Task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the EEG recording file exists in the user's Documents folder
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TARGET_FILE="${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
mkdir -p "$RECORDINGS_DIR"

# Check locations for the source file (installed by environment setup)
SOURCE_FILE=""
if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"
fi

if [ -n "$SOURCE_FILE" ]; then
    echo "Copying EEG recording from $SOURCE_FILE to $TARGET_FILE..."
    cp "$SOURCE_FILE" "$TARGET_FILE"
    chown ga:ga "$TARGET_FILE"
else
    echo "WARNING: Source EEG file not found. Creating a dummy file for structural validity (task may fail playback)."
    echo "%OpenBCI Raw EEG Data" > "$TARGET_FILE"
    echo "Sample Index, EXG Channel 0, EXG Channel 1, EXG Channel 2, EXG Channel 3, EXG Channel 4, EXG Channel 5, EXG Channel 6, EXG Channel 7" >> "$TARGET_FILE"
    for i in {1..1000}; do echo "$i,0,0,0,0,0,0,0,0" >> "$TARGET_FILE"; done
    chown ga:ga "$TARGET_FILE"
fi

# Ensure Screenshots directory exists and is empty of target file
SCREENSHOTS_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"
mkdir -p "$SCREENSHOTS_DIR"
rm -f "${SCREENSHOTS_DIR}/head_plot_session.png"
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# Kill any existing OpenBCI instances
pkill -f "OpenBCI_GUI" || true
sleep 1

# Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="