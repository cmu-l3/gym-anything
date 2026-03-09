#!/bin/bash
echo "=== Setting up bci_research_dashboard task ==="

source /workspace/utils/openbci_utils.sh || {
    echo "WARNING: Could not source openbci_utils.sh"
}

TASK_NAME="bci_research_dashboard"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
SCREENSHOTS_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"

su - ga -c "mkdir -p '$SETTINGS_DIR'"
su - ga -c "mkdir -p '$SCREENSHOTS_DIR'"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"

kill_openbci

# Record baseline
ls -la "$SETTINGS_DIR"/ 2>/dev/null > /tmp/${TASK_NAME}_initial_settings_list

INITIAL_SCREENSHOT_COUNT=$(count_screenshots)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# Record task start timestamp (AFTER baseline)
date +%s > /tmp/${TASK_NAME}_start_ts
touch /tmp/${TASK_NAME}_start_marker

echo "Launching OpenBCI GUI at Control Panel..."
launch_openbci

take_screenshot /tmp/${TASK_NAME}_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Agent must: start Synthetic session, switch to 6-panel layout, assign"
echo "Time Series/FFT Plot/Band Power/Accelerometer/Focus/Head Plot to each panel,"
echo "set notch filter to 60 Hz, enable Expert Mode, take screenshot (m key), save settings."
