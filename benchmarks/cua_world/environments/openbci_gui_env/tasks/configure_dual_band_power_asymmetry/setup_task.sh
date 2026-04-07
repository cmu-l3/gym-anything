#!/bin/bash
set -e
echo "=== Setting up Dual Band Power Asymmetry Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the recording directory exists
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"

# Ensure the specific playback file is available
# We check the standard installation locations for the backup file
SOURCE_FILE=""
if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"
elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt"
fi

if [ -n "$SOURCE_FILE" ]; then
    echo "Copying playback file from $SOURCE_FILE..."
    cp "$SOURCE_FILE" "$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"
    chown ga:ga "$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"
else
    echo "WARNING: Playback file not found. Task may be impossible."
    # Create a dummy file just in case, though it won't play valid data
    touch "$RECORDINGS_DIR/OpenBCI-EEG-S001-EyesOpen.txt"
fi

# Ensure Screenshots directory exists and is empty of target file
mkdir -p "/home/ga/Documents/OpenBCI_GUI/Screenshots"
rm -f "/home/ga/Documents/OpenBCI_GUI/Screenshots/asymmetry_setup.png"
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# Launch OpenBCI GUI
# The agent expects the GUI to be open but NO session active
echo "Launching OpenBCI GUI..."
launch_openbci

# Wait for window and maximize
wait_for_openbci 60
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="