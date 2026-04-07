#!/bin/bash
echo "=== Setting up isolate_motor_channels_screenshot task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# 1. Record task start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Ensure the specific Motor Imagery recording exists in the user's Documents
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TARGET_FILE="${RECORDINGS_DIR}/OpenBCI-EEG-S001-MotorImagery.txt"
SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-MotorImagery.txt"

mkdir -p "$RECORDINGS_DIR"

if [ ! -f "$TARGET_FILE" ]; then
    echo "Copying motor imagery file..."
    if [ -f "$SOURCE_FILE" ]; then
        cp "$SOURCE_FILE" "$TARGET_FILE"
    elif [ -f "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt" ]; then
        cp "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt" "$TARGET_FILE"
    else
        echo "WARNING: Motor imagery file not found in source locations."
        # Attempt fallback to eyes open if motor not available (to prevent total task breakage)
        if [ -f "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
            cp "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt" "$TARGET_FILE"
            echo "Fallback: Used EyesOpen file renamed as MotorImagery."
        fi
    fi
fi

# Set permissions
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# 3. Clean up previous screenshots to ensure we detect NEW ones
# We don't delete them, just note the count/latest for comparison, or move them
mkdir -p "/home/ga/Documents/OpenBCI_GUI/Screenshots"
# Move existing screenshots to a backup folder so the directory is clean for the agent
mkdir -p "/home/ga/Documents/OpenBCI_GUI/Screenshots/backup"
mv /home/ga/Documents/OpenBCI_GUI/Screenshots/*.png "/home/ga/Documents/OpenBCI_GUI/Screenshots/backup/" 2>/dev/null || true
mv /home/ga/Documents/OpenBCI_GUI/Screenshots/*.jpg "/home/ga/Documents/OpenBCI_GUI/Screenshots/backup/" 2>/dev/null || true

# 4. Launch OpenBCI GUI
# We want the agent to start from the System Control Panel, so we just launch it.
echo "Launching OpenBCI GUI..."
if command -v launch_openbci >/dev/null; then
    launch_openbci
else
    # Fallback if utils not loaded
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci"; then
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial state screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="