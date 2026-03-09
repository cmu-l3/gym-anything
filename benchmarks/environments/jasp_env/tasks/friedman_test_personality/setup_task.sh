#!/bin/bash
set -e
echo "=== Setting up Friedman Test task ==="

# Source shared utilities if available, otherwise define basics
mkdir -p /tmp
date +%s > /tmp/task_start_time.txt

# Clean previous artifacts
rm -f "/home/ga/Documents/JASP/Friedman_Analysis.jasp"
rm -f /tmp/task_result.json

# Dataset path (space-free name as per env setup)
DATA_PATH="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

# Verify dataset exists
if [ ! -f "$DATA_PATH" ]; then
    echo "ERROR: Dataset not found at $DATA_PATH"
    # Try to recover from backup/original location
    if [ -f "/opt/jasp_datasets/Big Five Personality Traits.csv" ]; then
        cp "/opt/jasp_datasets/Big Five Personality Traits.csv" "$DATA_PATH"
    else
        exit 1
    fi
fi

# Ensure JASP is closed
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

# Launch JASP with dataset
# Using setsid and nohup to ensure it persists
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp '$DATA_PATH' > /tmp/jasp_launch.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="