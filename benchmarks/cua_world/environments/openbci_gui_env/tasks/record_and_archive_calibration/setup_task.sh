#!/bin/bash
set -e
echo "=== Setting up Record and Archive Calibration Task ==="

# Load shared utilities
source /home/ga/openbci_task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Ensure the source recording file exists
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
SOURCE_FILE="OpenBCI-EEG-S001-EyesOpen.txt"

if [ ! -f "${RECORDINGS_DIR}/${SOURCE_FILE}" ]; then
    echo "Restoring source file..."
    # Try to copy from known locations
    if [ -f "/opt/openbci_data/${SOURCE_FILE}" ]; then
        cp "/opt/openbci_data/${SOURCE_FILE}" "${RECORDINGS_DIR}/${SOURCE_FILE}"
    elif [ -f "/workspace/data/${SOURCE_FILE}" ]; then
        cp "/workspace/data/${SOURCE_FILE}" "${RECORDINGS_DIR}/${SOURCE_FILE}"
    else
        echo "WARNING: Source file not found. Task may be impossible."
    fi
fi
chown ga:ga "${RECORDINGS_DIR}/${SOURCE_FILE}" 2>/dev/null || true

# 3. Clean up any previous target files (Anti-gaming)
TARGET_FILE="${RECORDINGS_DIR}/alpha_calibration.txt"
if [ -f "$TARGET_FILE" ]; then
    echo "Removing stale target file..."
    rm "$TARGET_FILE"
fi

# 4. Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
launch_openbci

# 5. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="