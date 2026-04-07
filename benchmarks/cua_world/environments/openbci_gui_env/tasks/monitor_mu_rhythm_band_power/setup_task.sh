#!/bin/bash
set -e
echo "=== Setting up Monitor Mu Rhythm task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Data Directories exist
mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots
mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings

# 3. Ensure the specific Motor Imagery file is present
TARGET_FILE="/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-MotorImagery.txt"
SOURCE_FILE=""

# Check potential source locations from env setup
if [ -f "/opt/openbci_data/OpenBCI-EEG-S001-MotorImagery.txt" ]; then
    SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-MotorImagery.txt"
elif [ -f "/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt" ]; then
    SOURCE_FILE="/workspace/data/OpenBCI-EEG-S001-MotorImagery.txt"
fi

if [ -n "$SOURCE_FILE" ]; then
    echo "Copying Motor Imagery file from $SOURCE_FILE..."
    cp "$SOURCE_FILE" "$TARGET_FILE"
    chown ga:ga "$TARGET_FILE"
else
    # Fallback: create a dummy file if real data is missing (should not happen in valid env)
    echo "WARNING: Real Motor Imagery file not found. Creating placeholder."
    echo "%OpenBCI Raw EEG Data" > "$TARGET_FILE"
    echo "%Sample Rate = 250 Hz" >> "$TARGET_FILE"
    # Generate 1000 lines of dummy CSV data
    for i in {1..1000}; do echo "$i,0,0,0,0,0,0,0,0" >> "$TARGET_FILE"; done
    chown ga:ga "$TARGET_FILE"
fi

# 4. Clean up previous results
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/mu_rhythm_config.png

# 5. Launch OpenBCI GUI if not running
if ! pgrep -f "OpenBCI_GUI" > /dev/null; then
    echo "Launching OpenBCI GUI..."
    # Use the utility function if available, otherwise manual launch
    if type launch_openbci >/dev/null 2>&1; then
        launch_openbci
    else
        su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /dev/null 2>&1 &"
        # Wait for window
        for i in {1..45}; do
            if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI"; then break; fi
            sleep 1
        done
    fi
fi

# 6. Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="