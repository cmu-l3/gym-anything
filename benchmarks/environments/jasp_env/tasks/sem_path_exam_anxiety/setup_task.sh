#!/bin/bash
echo "=== Setting up sem_path_exam_anxiety task ==="

# 1. Kill any running JASP instances to ensure clean state
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

# 2. Prepare the dataset
DATA_DIR="/home/ga/Documents/JASP"
DATASET="$DATA_DIR/ExamAnxiety.csv"
SOURCE_DATA="/opt/jasp_datasets/Exam Anxiety.csv"

mkdir -p "$DATA_DIR"
chown ga:ga "$DATA_DIR"

if [ -f "$SOURCE_DATA" ]; then
    cp "$SOURCE_DATA" "$DATASET"
    chown ga:ga "$DATASET"
    echo "Dataset copied to $DATASET"
else
    echo "ERROR: Source dataset not found at $SOURCE_DATA"
    exit 1
fi

# 3. Clean up previous run artifacts
rm -f "$DATA_DIR/Exam_Path_Model.jasp"
rm -f "$DATA_DIR/Model_Fit_Report.txt"

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch JASP
# Use setsid to detach from shell, redirect output
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 7. Maximize window and handle potential dialogs
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Attempt to dismiss "Welcome" or "Update" dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="