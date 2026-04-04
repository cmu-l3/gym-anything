#!/bin/bash
set -e
echo "=== Setting up Bayesian ANCOVA Task ==="

# 1. Record start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
OUTPUT_FILE="/home/ga/Documents/JASP/BayesianANCOVA_ExamAnxiety.jasp"
rm -f "$OUTPUT_FILE"
rm -f /tmp/task_result.json

# 3. Ensure dataset exists
DATASET="/home/ga/Documents/JASP/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from backup..."
    cp "/opt/jasp_datasets/Exam Anxiety.csv" "$DATASET" 2>/dev/null || \
    cp "/home/ga/Documents/JASP/ExamAnxiety.csv" "$DATASET" 2>/dev/null || true
    chown ga:ga "$DATASET"
fi

# 4. Kill existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# 5. Launch JASP with dataset
# Use setsid to detach from shell, ensure it survives
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
sleep 5 # Allow UI to settle

# 7. Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true
sleep 1

# 8. Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="