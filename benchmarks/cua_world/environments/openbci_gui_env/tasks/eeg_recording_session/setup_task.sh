#!/bin/bash
echo "=== Setting up eeg_recording_session task ==="

source /workspace/utils/openbci_utils.sh || {
    echo "WARNING: Could not source openbci_utils.sh"
}

TASK_NAME="eeg_recording_session"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
SCREENSHOTS_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"

su - ga -c "mkdir -p '$SETTINGS_DIR'"
su - ga -c "mkdir -p '$SCREENSHOTS_DIR'"
su - ga -c "mkdir -p '$RECORDINGS_DIR'"

kill_openbci

# Record initial state of recording files directory
# (we need to detect NEW recordings created during the task)
# List existing recording files with their sizes to detect new ones later
ls -la "$RECORDINGS_DIR"/ 2>/dev/null > /tmp/${TASK_NAME}_initial_recordings_list
echo "Initial recordings:"
cat /tmp/${TASK_NAME}_initial_recordings_list

# Record count and names of existing recordings (to detect new ones)
find "$RECORDINGS_DIR" -maxdepth 1 -type f \( -name "OpenBCI-*.txt" -o -name "BrainFlow-*.csv" \) \
    ! -name "OpenBCI-EEG-S001-*" \
    2>/dev/null > /tmp/${TASK_NAME}_existing_recording_names
echo "Existing recording names (excluding pre-placed EEG files):"
cat /tmp/${TASK_NAME}_existing_recording_names

# Record baseline settings
ls -la "$SETTINGS_DIR"/ 2>/dev/null > /tmp/${TASK_NAME}_initial_settings_list

# Record baseline screenshot count
INITIAL_SCREENSHOT_COUNT=$(count_screenshots)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts
touch /tmp/${TASK_NAME}_start_marker

echo "Launching OpenBCI GUI at Control Panel..."
launch_openbci

take_screenshot /tmp/${TASK_NAME}_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Agent must: start Synthetic session, set 4-panel layout (Time Series/Band Power/FFT Plot/Accelerometer),"
echo "set bandpass 1-50 Hz, set notch 60 Hz, enable Expert Mode,"
echo "START recording, take screenshot (m key), STOP recording, save settings."
