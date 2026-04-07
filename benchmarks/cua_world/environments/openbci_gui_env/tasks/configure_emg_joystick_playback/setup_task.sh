#!/bin/bash
set -e
echo "=== Setting up EMG Joystick Configuration Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI GUI is NOT running initially
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Ensure the required recording file exists
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
REQUIRED_FILE="OpenBCI-EEG-S001-MotorImagery.txt"
SOURCE_FILE="/opt/openbci_data/$REQUIRED_FILE"

mkdir -p "$RECORDINGS_DIR"
mkdir -p "/home/ga/Documents/OpenBCI_GUI/Screenshots"

if [ -f "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" "$RECORDINGS_DIR/$REQUIRED_FILE"
    echo "Restored recording file from backup."
elif [ ! -f "$RECORDINGS_DIR/$REQUIRED_FILE" ]; then
    # Fallback if not in opt (should be there from env setup)
    echo "WARNING: Primary source file not found. Checking alternate locations..."
    find /workspace/data -name "*MotorImagery*" -exec cp {} "$RECORDINGS_DIR/$REQUIRED_FILE" \;
fi

# Set permissions
chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# Remove any previous attempt screenshots to prevent false positives
rm -f "/home/ga/Documents/OpenBCI_GUI/Screenshots/emg_joystick_config.png"

# Start the application to the Control Panel (initial state)
echo "Starting OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="