#!/bin/bash
set -e
echo "=== Setting up navigate_playback_timestamp task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh || {
    echo "WARNING: Could not source openbci_task_utils.sh"
    # Define fallback if missing
    launch_openbci() {
        pkill -f "OpenBCI_GUI" || true
        su - ga -c "bash /home/ga/launch_openbci.sh > /dev/null 2>&1 &"
        sleep 10
    }
    take_screenshot() {
        DISPLAY=:1 scrot "$1" || true
    }
}

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure the specific data file exists
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TARGET_FILE="OpenBCI-EEG-S001-MotorImagery.txt"
SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-MotorImagery.txt"
FALLBACK_SOURCE="/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt"

mkdir -p "$RECORDINGS_DIR"

if [ ! -f "$RECORDINGS_DIR/$TARGET_FILE" ]; then
    echo "Copying required recording file..."
    if [ -f "$SOURCE_FILE" ]; then
        cp "$SOURCE_FILE" "$RECORDINGS_DIR/$TARGET_FILE"
    elif [ -f "$FALLBACK_SOURCE" ]; then
        cp "$FALLBACK_SOURCE" "$RECORDINGS_DIR/$TARGET_FILE"
    else
        echo "ERROR: Motor Imagery data file not found in /opt or /workspace."
        # Create a dummy file to prevent instant fail, but warn loudly
        echo "DUMMY DATA - REAL DATA MISSING" > "$RECORDINGS_DIR/$TARGET_FILE"
    fi
    chown ga:ga "$RECORDINGS_DIR/$TARGET_FILE"
fi

# 3. Ensure OpenBCI GUI is running (Clean Start)
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    echo "Killing existing OpenBCI instance..."
    pkill -f "OpenBCI_GUI" || true
    sleep 2
fi

echo "Launching OpenBCI GUI..."
launch_openbci

# 4. Wait for window and maximize
if wait_for_openbci 45; then
    echo "OpenBCI GUI window detected."
    # Maximize window
    DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus window
    DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true
else
    echo "WARNING: OpenBCI GUI did not start in time."
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="