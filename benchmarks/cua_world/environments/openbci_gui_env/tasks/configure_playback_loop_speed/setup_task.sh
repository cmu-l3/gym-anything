#!/bin/bash
set -e
echo "=== Setting up Configure Playback Speed task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ============================================================
# Ensure Data Availability
# ============================================================
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"

TARGET_FILE="OpenBCI-EEG-S001-MotorImagery.txt"
DEST_PATH="${RECORDINGS_DIR}/${TARGET_FILE}"

# Locate the source file (pre-downloaded in image or mounted)
SOURCE_FILE=""
for candidate in \
    "/opt/openbci_data/${TARGET_FILE}" \
    "/workspace/data/${TARGET_FILE}" \
    "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt"; do
    if [ -f "$candidate" ]; then
        SOURCE_FILE="$candidate"
        break
    fi
done

if [ -n "$SOURCE_FILE" ]; then
    echo "Copying EEG data from $SOURCE_FILE to $DEST_PATH"
    cp "$SOURCE_FILE" "$DEST_PATH"
    chown ga:ga "$DEST_PATH"
else
    echo "WARNING: Motor Imagery EEG file not found. Creating a placeholder for testing (task may be harder)."
    # Create a dummy file just so file selector isn't empty, though playback won't look right
    echo "%OpenBCI Raw EEG Data" > "$DEST_PATH"
    echo "%Sample Rate = 250 Hz" >> "$DEST_PATH"
    for i in {1..1000}; do echo "0,0,0,0,0,0,0,0" >> "$DEST_PATH"; done
    chown ga:ga "$DEST_PATH"
fi

# ============================================================
# Application State Setup
# ============================================================
# Kill any existing instances to ensure fresh start
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI (starts at System Control Panel by default)
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window
echo "Waiting for OpenBCI window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" >/dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Ensure Screenshots directory exists and is empty of previous task artifacts
mkdir -p "/home/ga/Documents/OpenBCI_GUI/Screenshots"
rm -f "/home/ga/Documents/OpenBCI_GUI/Screenshots/playback_review_config.png"

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="