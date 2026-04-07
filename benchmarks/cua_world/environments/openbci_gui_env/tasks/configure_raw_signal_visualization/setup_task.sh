#!/bin/bash
set -e
echo "=== Setting up Configure Raw Signal Visualization Task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Prepare Data
# ============================================================
echo "Preparing EEG playback data..."
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"

# Ensure the specific playback file exists
TARGET_FILE="${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"

# Search locations: install dir, workspace data, or generated location
FOUND_SRC=""
for candidate in \
    "/opt/openbci_data/OpenBCI-EEG-S001-EyesOpen.txt" \
    "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" \
    "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" \
    "/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"; do
    if [ -f "$candidate" ] && [ "$(wc -c < "$candidate")" -gt 10000 ]; then
        FOUND_SRC="$candidate"
        break
    fi
done

if [ -n "$FOUND_SRC" ] && [ "$FOUND_SRC" != "$TARGET_FILE" ]; then
    cp "$FOUND_SRC" "$TARGET_FILE"
    echo "Copied data from $FOUND_SRC to $TARGET_FILE"
elif [ -f "$TARGET_FILE" ]; then
    echo "Data file already exists at target location."
else
    echo "WARNING: Could not find EEG data file. Task may be impossible."
    # Create a dummy file if absolutely necessary to prevent immediate failure, 
    # though valid playback requires real data.
    touch "$TARGET_FILE"
fi

chown -R ga:ga "/home/ga/Documents/OpenBCI_GUI"

# ============================================================
# 2. Reset Application State
# ============================================================
# Kill any running instances
pkill -f "OpenBCI_GUI" || true
sleep 2

# Remove any previous screenshots to prevent false positives
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/raw_signal_view.png

# Launch OpenBCI GUI to the main menu (System Control Panel)
echo "Launching OpenBCI GUI..."
# Using the wrapper or direct launch
if [ -f "/home/ga/launch_openbci.sh" ]; then
    su - ga -c "setsid /home/ga/launch_openbci.sh > /dev/null 2>&1 &"
else
    su - ga -c "setsid openbci_gui > /dev/null 2>&1 &"
fi

# Wait for window
echo "Waiting for OpenBCI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# Take initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="