#!/bin/bash
echo "=== Setting up polynomial_regression_exam_anxiety task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure JASP is clean
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

# 3. Ensure the dataset exists
DATASET="/home/ga/Documents/JASP/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jasp_datasets..."
    mkdir -p /home/ga/Documents/JASP
    cp "/opt/jasp_datasets/Exam Anxiety.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 4. Remove any previous result file to prevent false positives
rm -f "/home/ga/Documents/JASP/Polynomial_Exam.jasp"

# 5. Launch JASP with the dataset
# Using setsid to ensure process survives su exit
# The launch-jasp wrapper handles the flatpak run command
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 7. Handle window state and dialogs
sleep 5
# Dismiss potential "Check for updates" or welcome dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure it is focused
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 8. Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="