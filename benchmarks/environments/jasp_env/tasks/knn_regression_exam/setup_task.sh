#!/bin/bash
set -e
echo "=== Setting up KNN Regression Exam Anxiety task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure dataset exists and is accessible
DATASET="/home/ga/Documents/JASP/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset..."
    cp "/opt/jasp_datasets/Exam Anxiety.csv" "$DATASET"
fi
chown ga:ga "$DATASET"

# Remove any previous result file to prevent false positives
rm -f /home/ga/Documents/JASP/knn_exam_results.jasp

# Kill any running JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Launch JASP with the ExamAnxiety dataset
# Uses setsid so the process survives when su exits
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_task.log 2>&1 &"

# Wait for JASP window to appear
echo "Waiting for JASP to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Wait extra time for the data to fully load into the grid
sleep 15

# Dismiss any potential startup dialogs (like "Check for updates")
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Maximize the JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="