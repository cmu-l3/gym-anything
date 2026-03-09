#!/bin/bash
set -e
echo "=== Setting up JASP Exploratory Plot Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f "/home/ga/Documents/JASP/ExploratoryPlot.jasp"
rm -f /tmp/task_result.json

# 3. Ensure Dataset Exists
DATASET="/home/ga/Documents/JASP/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset..."
    cp "/opt/jasp_datasets/Exam Anxiety.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 4. Kill existing JASP instances
pkill -f "org.jaspstats.JASP" || true
sleep 2

# 5. Launch JASP with the dataset
# Using setsid to detach from the shell so it persists
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for Window
echo "Waiting for JASP window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 7. Handle First-Run Dialogs (if any remain) & Maximize
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Attempt to dismiss potential welcome/update dialogs blindly
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Ensure window is focused
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 8. Capture Initial State Screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="