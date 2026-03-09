#!/bin/bash
set -e
echo "=== Setting up Bayesian Correlation Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f "/home/ga/Documents/JASP/BayesianCorrelationExam.jasp"
rm -f /tmp/task_result.json

# Ensure the dataset exists in the documents folder
DATASET_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"

mkdir -p /home/ga/Documents/JASP

if [ ! -f "$DATASET_DEST" ]; then
    echo "Copying dataset..."
    if [ -f "$DATASET_SOURCE" ]; then
        cp "$DATASET_SOURCE" "$DATASET_DEST"
    else
        # Fallback if opt dataset missing, though env should have it
        echo "WARNING: Source dataset not found in /opt, creating placeholder for testing (should not happen in prod)"
        echo "Code,Revise,Exam,Anxiety,Gender" > "$DATASET_DEST"
        echo "1,4,40,86.298,Male" >> "$DATASET_DEST"
    fi
    chown ga:ga "$DATASET_DEST"
fi

# Kill any running JASP instances to ensure fresh start
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Start JASP (empty)
# We start it empty so the agent has to perform the "Open file" action as part of the task
echo "Starting JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Wait a bit for UI to initialize
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="