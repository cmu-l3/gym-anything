#!/bin/bash
echo "=== Setting up motor_imagery_channel_protocol task ==="

source /workspace/utils/openbci_utils.sh || {
    echo "WARNING: Could not source openbci_utils.sh"
}

TASK_NAME="motor_imagery_channel_protocol"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"

# Ensure recording file exists
if [ ! -f "${RECORDINGS_DIR}/OpenBCI-EEG-S001-MotorImagery.txt" ]; then
    echo "ERROR: Motor imagery recording file not found!"
    echo "Expected: ${RECORDINGS_DIR}/OpenBCI-EEG-S001-MotorImagery.txt"
    echo "Available files in Recordings/:"
    ls -la "$RECORDINGS_DIR/" 2>/dev/null || echo "(none)"
    exit 1
fi
echo "Motor imagery recording file verified: ${RECORDINGS_DIR}/OpenBCI-EEG-S001-MotorImagery.txt"

# Kill any running OpenBCI instance
kill_openbci

# Record baseline: settings files with timestamps
ls -la "$SETTINGS_DIR"/ 2>/dev/null > /tmp/${TASK_NAME}_initial_settings_list
echo "Initial settings files:"
cat /tmp/${TASK_NAME}_initial_settings_list

# Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# Create timestamp marker file
touch /tmp/${TASK_NAME}_start_marker

# Launch OpenBCI GUI at Control Panel
# Agent must select PLAYBACK mode and the Motor Imagery file
echo "Launching OpenBCI GUI at Control Panel..."
launch_openbci

take_screenshot /tmp/${TASK_NAME}_initial_screenshot.png

echo "Recording file available at: ${RECORDINGS_DIR}/OpenBCI-EEG-S001-MotorImagery.txt"
echo "Channel mapping: Ch1=Fp1, Ch2=Fp2, Ch3=C3, Ch4=C4, Ch5=P7, Ch6=P8, Ch7=O1, Ch8=O2"
echo ""
echo "=== Setup Complete ==="
echo "Agent must: select PLAYBACK mode, load MotorImagery.txt, disable channels 1/2/5/6/7/8,"
echo "set bandpass 8-30 Hz, add FFT Plot widget, and save settings."
