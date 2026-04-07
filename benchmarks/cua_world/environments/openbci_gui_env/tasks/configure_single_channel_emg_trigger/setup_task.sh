#!/bin/bash
set -e
echo "=== Setting up Configure Single-Channel EMG Task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure Data Availability
# ============================================================
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TARGET_FILE="OpenBCI-EEG-S001-MotorImagery.txt"
SOURCE_FILE="/opt/openbci_data/$TARGET_FILE"

mkdir -p "$RECORDINGS_DIR"

if [ ! -f "$RECORDINGS_DIR/$TARGET_FILE" ]; then
    echo "Target recording not found in Documents. Attempting to restore..."
    
    # Try /opt location first
    if [ -f "$SOURCE_FILE" ]; then
        cp "$SOURCE_FILE" "$RECORDINGS_DIR/$TARGET_FILE"
        echo "Restored from $SOURCE_FILE"
    # Try workspace location
    elif [ -f "/workspace/data/$TARGET_FILE" ]; then
        cp "/workspace/data/$TARGET_FILE" "$RECORDINGS_DIR/$TARGET_FILE"
        echo "Restored from workspace data"
    else
        echo "CRITICAL WARNING: Playback file $TARGET_FILE not found anywhere!"
        # create a dummy file just to prevent total blockage, though task will be harder
        echo "%OpenBCI Raw EEG Data" > "$RECORDINGS_DIR/$TARGET_FILE"
        echo "Dummy data for verification" >> "$RECORDINGS_DIR/$TARGET_FILE"
    fi
fi

# Ensure correct ownership
chown -R ga:ga "$RECORDINGS_DIR"

# ============================================================
# 2. Launch OpenBCI GUI
# ============================================================
echo "Launching OpenBCI GUI..."

# Kill any existing instances to ensure clean state
pkill -f "OpenBCI_GUI" || true
sleep 1

# Launch as ga user
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"

# Wait for window
echo "Waiting for OpenBCI window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
        echo "OpenBCI GUI detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Give it a moment to render the System Control Panel
sleep 5

# ============================================================
# 3. Capture Initial State
# ============================================================
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="