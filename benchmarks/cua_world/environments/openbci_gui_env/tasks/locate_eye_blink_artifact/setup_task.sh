#!/bin/bash
set -e
echo "=== Setting up Locate Eye Blink Artifact Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/blink_timestamp.txt
rm -f /tmp/task_result.json

# 3. Ensure the specific recording file exists in the correct location
# The environment setup typically places it, but we verify here.
REC_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TARGET_FILE="OpenBCI-EEG-S001-EyesOpen.txt"
SOURCE_FILE="/opt/openbci_data/${TARGET_FILE}"

mkdir -p "$REC_DIR"

if [ ! -f "${REC_DIR}/${TARGET_FILE}" ]; then
    echo "Recording file not found in Documents, copying from source..."
    if [ -f "$SOURCE_FILE" ]; then
        cp "$SOURCE_FILE" "${REC_DIR}/${TARGET_FILE}"
    elif [ -f "/workspace/data/${TARGET_FILE}" ]; then
        cp "/workspace/data/${TARGET_FILE}" "${REC_DIR}/${TARGET_FILE}"
    else
        echo "ERROR: Source EEG file not found!"
        # Fallback creation of a dummy file if real data is missing (should not happen in prod)
        # This prevents the task from being impossible if data download failed
        echo "%OpenBCI Raw EEG Data" > "${REC_DIR}/${TARGET_FILE}"
        echo "%Sample Rate = 250 Hz" >> "${REC_DIR}/${TARGET_FILE}"
        echo "Sample Index, Channel 1, Channel 2" >> "${REC_DIR}/${TARGET_FILE}"
        # Generate 10 seconds of noise
        for i in {0..2500}; do echo "$i, 10.5, 12.3"; done >> "${REC_DIR}/${TARGET_FILE}"
    fi
fi

# Ensure correct permissions
chown ga:ga "${REC_DIR}/${TARGET_FILE}"

# 4. Launch OpenBCI GUI to the Control Panel
echo "Launching OpenBCI GUI..."
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 1

# Using the utility function or direct launch
if command -v launch_openbci >/dev/null 2>&1; then
    launch_openbci
else
    # Manual launch fallback
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci.log 2>&1 &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
            break
        fi
        sleep 1
    done
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="