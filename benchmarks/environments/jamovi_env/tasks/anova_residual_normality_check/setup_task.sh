#!/bin/bash
set -e
echo "=== Setting up ANOVA Residual Normality Check task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring ToothGrowth.csv..."
    cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# Clean up previous attempts
rm -f "/home/ga/Documents/Jamovi/ToothGrowth_Residuals.omv"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Start Jamovi (empty, so agent must open file)
# Using setsid to detach from shell
echo "Starting Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="