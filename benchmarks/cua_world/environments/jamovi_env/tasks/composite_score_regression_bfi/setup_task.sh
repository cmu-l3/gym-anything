#!/bin/bash
set -e
echo "=== Setting up composite_score_regression_bfi task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f "/home/ga/Documents/Jamovi/NeuroticismAnalysis.omv"
rm -f "/home/ga/Documents/Jamovi/regression_results.txt"

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    # Fallback if specific BFI25 script wasn't run in env setup, though it should be
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
         python3 /opt/jamovi_datasets/extract_bfi25.py
         mv "/home/ga/Documents/Jamovi/BFI25.csv" "$DATASET" 2>/dev/null || true
    fi
fi

# Double check dataset exists
if [ ! -f "$DATASET" ]; then
    echo "ERROR: Dataset $DATASET not found."
    exit 1
fi
chown ga:ga "$DATASET"

echo "Dataset ready: $DATASET"

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Open Jamovi with the dataset pre-loaded
# Using setsid to detach from shell so it persists
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear (Jamovi Electron app takes a moment)
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Wait a bit more for UI to be responsive
sleep 15

# Dismiss any startup dialogs (like 'Welcome' or 'Update') if they appear
# Escape key usually closes them
su - ga -c "DISPLAY=:1 xdotool key Escape 2>/dev/null" || true
sleep 1

# Maximize the window to ensure buttons are visible
# Note: Jamovi window title often reflects the filename
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -i "jamovi" | head -n 1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Maximizing window $WINDOW_ID..."
    DISPLAY=:1 wmctrl -ir "$WINDOW_ID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WINDOW_ID"
fi

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="