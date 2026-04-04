#!/bin/bash
echo "=== Setting up computed_variable_efficiency task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing JASP instances to ensure fresh start
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

# Ensure the dataset exists with the correct name (Space-free)
# The environment setup already copies them to /home/ga/Documents/JASP/
DATASET_SOURCE="/home/ga/Documents/JASP/ExamAnxiety.csv"
DATASET_BACKUP="/opt/jasp_datasets/Exam Anxiety.csv"

if [ ! -f "$DATASET_SOURCE" ]; then
    echo "Restoring dataset from backup..."
    mkdir -p /home/ga/Documents/JASP
    cp "$DATASET_BACKUP" "$DATASET_SOURCE" 2>/dev/null || echo "Error: Source dataset not found"
fi

# Ensure correct permissions
chown ga:ga "$DATASET_SOURCE"

# Clean up any previous run artifacts
rm -f /home/ga/Documents/JASP/efficiency_data.csv
rm -f /home/ga/Documents/JASP/efficiency_analysis.jasp

echo "Dataset ready: $DATASET_SOURCE"

# Launch JASP with the dataset loaded
# Using the launcher script provided by the environment
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET_SOURCE' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# Wait a bit for the data to actually load into the grid
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any potential "Welcome" or "Update" dialogs if they appear
# (The environment setup disables updates, but just in case)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="