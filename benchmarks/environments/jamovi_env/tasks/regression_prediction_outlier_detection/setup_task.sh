#!/bin/bash
set -e
echo "=== Setting up regression_prediction_outlier_detection task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f "/home/ga/Documents/Jamovi/Exam_Outlier_Analysis.omv"
rm -f "/home/ga/Documents/Jamovi/outlier_student.txt"

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Ensure the dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATASET"
    chown -R ga:ga "/home/ga/Documents/Jamovi"
fi

echo "Dataset ready: $DATASET"

# Open Jamovi with the dataset pre-loaded.
# Using setsid to detach from the shell so it survives.
echo "Starting Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_task.log 2>&1 &"

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the Jamovi window
# Note: Jamovi window title usually matches the filename
DISPLAY=:1 wmctrl -r "ExamAnxiety" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ExamAnxiety" 2>/dev/null || true

# Wait a moment for UI to settle
sleep 5

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="