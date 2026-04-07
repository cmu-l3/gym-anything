#!/bin/bash
echo "=== Setting up extract_eeg_clip task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI GUI is closed initially
pkill -f "OpenBCI_GUI" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true
sleep 2

# Directories
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"

# Ensure the source file exists
SOURCE_FILE="OpenBCI-EEG-S001-MotorImagery.txt"
SOURCE_PATH="$RECORDINGS_DIR/$SOURCE_FILE"

# Look for the source file in likely locations if not present
if [ ! -f "$SOURCE_PATH" ]; then
    echo "Source file not found in Recordings, searching..."
    FOUND_SRC=""
    for candidate in \
        "/opt/openbci_data/$SOURCE_FILE" \
        "/workspace/data/$SOURCE_FILE" \
        "/home/ga/Documents/$SOURCE_FILE"; do
        if [ -f "$candidate" ]; then
            FOUND_SRC="$candidate"
            break
        fi
    done
    
    if [ -n "$FOUND_SRC" ]; then
        echo "Copying source from $FOUND_SRC..."
        cp "$FOUND_SRC" "$SOURCE_PATH"
        chown ga:ga "$SOURCE_PATH"
    else
        echo "WARNING: Source EEG file not found! creating a dummy placeholder for robustness (though task may fail)"
        # Create a dummy file just so the agent sees something, though it won't be real EEG
        echo "%OpenBCI Raw EEG Data" > "$SOURCE_PATH"
        echo "%Sample Rate = 250 Hz" >> "$SOURCE_PATH"
        for i in {1..5000}; do echo "$i,0,0,0,0,0,0,0,0" >> "$SOURCE_PATH"; done
        chown ga:ga "$SOURCE_PATH"
    fi
fi

# Record initial file list to detect new files later
ls -1 "$RECORDINGS_DIR" > /tmp/initial_file_list.txt

# Launch OpenBCI GUI
# We want to launch it but NOT start the session automatically, 
# so the agent has to choose "Playback"
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# Wait for window
wait_for_openbci 45

# Maximize window
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="