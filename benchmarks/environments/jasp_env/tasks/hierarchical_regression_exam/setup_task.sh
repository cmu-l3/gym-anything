#!/bin/bash
set -e
echo "=== Setting up Hierarchical Regression Task ==="

# 1. Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists in User Documents
DATA_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATA_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"

mkdir -p "$(dirname "$DATA_DEST")"

if [ -f "$DATA_SOURCE" ]; then
    cp "$DATA_SOURCE" "$DATA_DEST"
    chown ga:ga "$DATA_DEST"
    echo "Dataset copied to $DATA_DEST"
else
    echo "ERROR: Source dataset not found at $DATA_SOURCE"
    # Fallback for dev environments if /opt is empty
    touch "$DATA_DEST"
fi

# 3. Clean up previous artifacts
rm -f "/home/ga/Documents/JASP/Hierarchical_Exam.jasp"
rm -f "/home/ga/Documents/JASP/hierarchical_report.txt"

# 4. Launch JASP with the dataset
# Using setsid so it survives shell exit, pointing to the launcher wrapper
echo "Launching JASP..."
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATA_DEST\" > /tmp/jasp_launch.log 2>&1 &"
    
    # Wait for window (JASP is heavy, give it time)
    for i in {1..40}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected."
            break
        fi
        sleep 1
    done
fi

# 5. Maximize and Focus Window
# Wait a bit for the UI to actually render inside the window
sleep 5
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="