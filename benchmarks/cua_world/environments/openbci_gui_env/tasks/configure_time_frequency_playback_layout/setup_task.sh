#!/bin/bash
set -e
echo "=== Setting up Configure Time-Frequency Playback Layout task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure the recordings directory exists
mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings

# Verify the playback file exists. 
# The environment setup usually places it, but we verify here.
PLAYBACK_FILE="/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"
SOURCE_FILE="/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt"

if [ ! -f "$PLAYBACK_FILE" ]; then
    echo "Playback file not found in Documents. Attempting to restore..."
    if [ -f "$SOURCE_FILE" ]; then
        cp "$SOURCE_FILE" "$PLAYBACK_FILE"
        chown ga:ga "$PLAYBACK_FILE"
        echo "Restored playback file from /opt/openbci_data/"
    else
        echo "ERROR: Playback file source missing. Task may be impossible."
        # We don't exit 1 here to allow the agent to potentially find it elsewhere or fail gracefully,
        # but we log the warning.
    fi
fi

# Ensure OpenBCI GUI is NOT running (start fresh)
pkill -f "OpenBCI_GUI" || true
sleep 2

# Launch OpenBCI GUI in the background (using the wrapper)
echo "Launching OpenBCI GUI..."
su - ga -c "setsid /usr/local/bin/openbci_gui > /dev/null 2>&1 &"

# Wait for the window to appear (Hub/Control Panel)
echo "Waiting for OpenBCI GUI window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Wait a moment for the interface to render
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="