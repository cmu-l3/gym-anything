#!/bin/bash
echo "=== Setting up alpha_neurofeedback_workspace task ==="

source /workspace/utils/openbci_utils.sh || {
    echo "WARNING: Could not source openbci_utils.sh"
}

TASK_NAME="alpha_neurofeedback_workspace"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
SCREENSHOTS_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"

# Ensure required directories exist
su - ga -c "mkdir -p '$SETTINGS_DIR'"
su - ga -c "mkdir -p '$SCREENSHOTS_DIR'"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"

# Kill any running OpenBCI instance
kill_openbci

# Record baseline: list existing settings files with modification times
# (so we can identify files created AFTER the task starts)
ls -la "$SETTINGS_DIR"/ 2>/dev/null > /tmp/${TASK_NAME}_initial_settings_list
echo "Initial settings files:"
cat /tmp/${TASK_NAME}_initial_settings_list

# Record baseline screenshot count
INITIAL_SCREENSHOT_COUNT=$(count_screenshots)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# Record task start timestamp (AFTER recording baseline — critical ordering)
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# Take a reference marker file for timestamp comparisons
touch /tmp/${TASK_NAME}_start_marker

# Launch OpenBCI GUI at the Control Panel (NOT auto-starting Synthetic)
# The agent must configure the workspace from scratch
echo "Launching OpenBCI GUI at Control Panel..."
launch_openbci

take_screenshot /tmp/${TASK_NAME}_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Agent must: start Synthetic session, set 4-panel layout, assign Time Series/FFT/Band Power/Focus widgets,"
echo "set bandpass 1-40 Hz, enable Expert Mode, take screenshot (m key), and save settings."
