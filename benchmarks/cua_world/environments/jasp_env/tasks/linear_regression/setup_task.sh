#!/bin/bash
echo "=== Setting up linear_regression task ==="

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# Ensure the dataset exists (space-free filename to avoid quoting issues)
DATASET="/home/ga/Documents/JASP/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jasp_datasets..."
    mkdir -p /home/ga/Documents/JASP
    cp "/opt/jasp_datasets/Exam Anxiety.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"

# Open JASP with the dataset pre-loaded.
# Uses setsid so the process survives when su exits.
# QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox is set inside the launcher script.
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET > /tmp/jasp_task.log 2>&1 &"
sleep 22

# Dismiss any dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== linear_regression task setup complete ==="
