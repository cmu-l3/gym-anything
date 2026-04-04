#!/bin/bash
set -e
echo "=== Setting up Binomial Test Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
OUTPUT_FILE="/home/ga/Documents/JASP/BinomialTestGender.jasp"
rm -f "$OUTPUT_FILE"
echo "Cleaned up previous output: $OUTPUT_FILE"

# 3. Ensure Dataset Exists
DATASET="/home/ga/Documents/JASP/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from source..."
    cp "/opt/jasp_datasets/Exam Anxiety.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 4. Kill any existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# 5. Launch JASP with the dataset
# We use setsid to ensure it survives the su session, and launch via the wrapper
echo "Launching JASP with dataset..."
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET\" > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP to start..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 7. Maximize and Focus
# Give it a moment to fully render the UI
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 8. Dismiss startup dialogs (if any remain)
# Press Escape twice to be safe against 'Welcome' or 'Update' dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="