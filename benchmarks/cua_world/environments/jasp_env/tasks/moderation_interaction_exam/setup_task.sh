#!/bin/bash
set -e
echo "=== Setting up Moderation Analysis Task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists
DATASET_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"

mkdir -p /home/ga/Documents/JASP
if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    echo "Dataset copied to $DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    exit 1
fi

# 3. Clean up previous run artifacts
rm -f "/home/ga/Documents/JASP/Moderation_Analysis.jasp"

# 4. Start JASP (Empty)
# Use setsid to ensure it survives shell exit
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
            echo "JASP window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Maximize JASP Window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="