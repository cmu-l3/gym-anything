#!/bin/bash
set -e
echo "=== Setting up log_log_regression_toothgrowth task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring ToothGrowth.csv..."
    if [ -f "/opt/jamovi_datasets/ToothGrowth.csv" ]; then
        cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATASET"
        chown ga:ga "$DATASET"
    else
        echo "ERROR: Source dataset not found in /opt/jamovi_datasets"
        exit 1
    fi
fi

# Clean up previous run artifacts
rm -f "/home/ga/Documents/Jamovi/PowerLaw_Analysis.omv"
rm -f "/home/ga/Documents/Jamovi/elasticity_report.txt"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (starting with empty state as per description)
# We launch it without a file so the agent has to perform the Open action
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the window
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any startup dialogs (Welcome screen often appears on fresh launch)
# Press Escape a couple of times to clear "Welcome" or "What's New"
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="