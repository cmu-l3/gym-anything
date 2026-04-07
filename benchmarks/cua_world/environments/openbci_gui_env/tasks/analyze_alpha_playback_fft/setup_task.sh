#!/bin/bash
set -e
echo "=== Setting up analyze_alpha_playback_fft task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ensure target directory exists
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"

# Ensure the specific recording file exists
# The environment setup tries to put it there, but we verify here
REQUIRED_FILE="/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"
BACKUP_SOURCE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"

if [ ! -f "$REQUIRED_FILE" ]; then
    echo "Copying recording file from backup..."
    if [ -f "$BACKUP_SOURCE" ]; then
        cp "$BACKUP_SOURCE" "$REQUIRED_FILE"
        chown ga:ga "$REQUIRED_FILE"
    else
        echo "WARNING: Recording file not found in backup location!"
        # Attempt to find it in workspace data if backup fails
        find /workspace/data -name "*EyesOpen*" -exec cp {} "$REQUIRED_FILE" \; -quit
        chown ga:ga "$REQUIRED_FILE"
    fi
fi

if [ ! -f "$REQUIRED_FILE" ]; then
    echo "ERROR: Could not locate required EEG recording file."
    exit 1
fi

echo "Verified recording file: $REQUIRED_FILE"

# Clean up previous artifacts
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/alpha_analysis.png

# Launch OpenBCI GUI to the start screen (System Control Panel)
echo "Launching OpenBCI GUI..."
launch_openbci

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="