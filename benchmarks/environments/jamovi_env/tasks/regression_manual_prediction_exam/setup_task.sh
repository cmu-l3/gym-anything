#!/bin/bash
set -e
echo "=== Setting up regression_manual_prediction_exam task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists in the user's documents
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATASET"
    chown ga:ga "$DATASET"
    chmod 644 "$DATASET"
fi

echo "Dataset ready: $DATASET"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi with the dataset pre-loaded
# Using setsid to detach from the shell so it persists
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Wait a bit for UI to settle
sleep 5

# Dismiss any potential first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize the window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "ExamAnxiety" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="