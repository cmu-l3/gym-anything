#!/bin/bash
set -e
echo "=== Setting up Logistic Regression Task ==="

# 1. Record Task Start Time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f "/home/ga/Documents/JASP/LogisticRegression_Cloak.jasp"
rm -f "/home/ga/Documents/JASP/logistic_report.txt"
rm -f /tmp/task_result.json

# 3. Ensure JASP is not running initially
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# 4. Verify Dataset Exists
DATASET="/home/ga/Documents/JASP/InvisibilityCloak.csv"
if [ ! -f "$DATASET" ]; then
    echo "ERROR: Dataset not found at $DATASET"
    # Try to recover from backup if available (handled by env setup usually)
    if [ -f "/opt/jasp_datasets/Invisibility Cloak.csv" ]; then
        cp "/opt/jasp_datasets/Invisibility Cloak.csv" "$DATASET"
    else
        echo "CRITICAL: Could not find source dataset."
        exit 1
    fi
fi

# 5. Launch JASP with the dataset
# Using the system-wide launcher wrapper which handles sandbox flags
echo "Launching JASP with dataset: $DATASET"
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET\" > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 7. Configure Window (Maximize and Focus)
# Allow a few seconds for the window to actually paint
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 8. Dismiss any startup dialogs (sometimes JASP shows "Welcome" or "Update")
# Press Escape a couple of times safely
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Capture Initial State Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="