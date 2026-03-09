#!/bin/bash
echo "=== Setting up eyes_open_alpha_analysis task ==="

source /workspace/utils/openbci_utils.sh || {
    echo "WARNING: Could not source openbci_utils.sh"
}

TASK_NAME="eyes_open_alpha_analysis"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
SCREENSHOTS_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"

su - ga -c "mkdir -p '$SETTINGS_DIR'"
su - ga -c "mkdir -p '$SCREENSHOTS_DIR'"
su - ga -c "mkdir -p '$RECORDINGS_DIR'"

# Verify the required recording file exists
EYES_OPEN_FILE="${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
if [ ! -f "$EYES_OPEN_FILE" ]; then
    echo "ERROR: Eyes Open recording file not found at: $EYES_OPEN_FILE"
    echo "Available files in Recordings/:"
    ls -la "$RECORDINGS_DIR/" 2>/dev/null || echo "(none)"
    exit 1
fi
echo "Eyes Open recording verified: $EYES_OPEN_FILE"
ls -la "$EYES_OPEN_FILE"

kill_openbci

# Record baseline
ls -la "$SETTINGS_DIR"/ 2>/dev/null > /tmp/${TASK_NAME}_initial_settings_list

INITIAL_SCREENSHOT_COUNT=$(count_screenshots)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts
touch /tmp/${TASK_NAME}_start_marker

echo "Launching OpenBCI GUI at Control Panel..."
launch_openbci

take_screenshot /tmp/${TASK_NAME}_initial_screenshot.png

echo "Recording available at: $EYES_OPEN_FILE"
echo ""
echo "=== Setup Complete ==="
echo "Agent must: select PLAYBACK mode, load EyesOpen.txt, add Band Power + FFT Plot widgets,"
echo "set bandpass 1-50 Hz, set timeseries scale 100 uV, enable Expert Mode,"
echo "take screenshot (m key), save settings."
