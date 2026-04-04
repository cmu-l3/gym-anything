#!/bin/bash
set -e
echo "=== Setting up Boosting Classification Task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/JASP/BoostingClassification.jasp
rm -f /tmp/task_result.json

# 3. Ensure Dataset Exists
DATASET="/home/ga/Documents/JASP/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring ToothGrowth.csv..."
    cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 4. Launch JASP with the dataset
# Using setsid and correct flags for the environment
echo "Launching JASP..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Allow UI to load
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture Initial State Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="