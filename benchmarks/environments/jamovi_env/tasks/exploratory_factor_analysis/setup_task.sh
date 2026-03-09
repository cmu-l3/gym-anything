#!/bin/bash
set -e
echo "=== Setting up Exploratory Factor Analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists and has correct permissions
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring BFI25.csv from backup..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
    else
        echo "ERROR: Dataset extraction script missing!"
        exit 1
    fi
fi
chown ga:ga "$DATASET"
chmod 644 "$DATASET"
echo "Dataset confirmed at $DATASET"

# Remove any previous result file to prevent false positives
rm -f "/home/ga/Documents/Jamovi/BFI25_EFA.omv"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (empty state)
# We use setsid to detach it from the shell so it persists
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Also try matching by class if title fails
DISPLAY=:1 wmctrl -x -r "jamovi.Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any potential welcome dialogs
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="