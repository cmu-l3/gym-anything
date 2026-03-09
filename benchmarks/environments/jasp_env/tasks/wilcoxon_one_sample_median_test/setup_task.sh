#!/bin/bash
set -e
echo "=== Setting up Wilcoxon One-Sample Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure JASP is closed
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Ensure the dataset exists and has correct permissions
DATASET_SRC="/opt/jasp_datasets/Exam Anxiety.csv"
DATASET_DST="/home/ga/Documents/JASP/ExamAnxiety.csv"
mkdir -p "$(dirname "$DATASET_DST")"

if [ -f "$DATASET_SRC" ]; then
    cp "$DATASET_SRC" "$DATASET_DST"
    chown ga:ga "$DATASET_DST"
    echo "Dataset prepared at $DATASET_DST"
else
    echo "ERROR: Source dataset not found at $DATASET_SRC"
    exit 1
fi

# Launch JASP with the dataset
# We use 'setsid' to detach the process so it survives the shell exit
# QT flags are handled in the launcher script created during env setup
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET_DST\" > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window to appear (can take 10-20s)
echo "Waiting for JASP window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Wait a bit more for UI to be responsive
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="