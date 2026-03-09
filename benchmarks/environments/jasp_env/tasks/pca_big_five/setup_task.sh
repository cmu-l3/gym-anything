#!/bin/bash
set -e
echo "=== Setting up PCA Big Five task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists and is clean
DATASET="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from source..."
    cp "/opt/jasp_datasets/Big Five Personality Traits.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 3. Cleanup previous run artifacts
rm -f "/home/ga/Documents/JASP/BigFive_PCA.jasp"
rm -f /tmp/task_result.json

# 4. Ensure JASP is running and ready
# We kill any existing instance to ensure a clean state
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

echo "Launching JASP..."
# Use setsid to detach from shell, ensure correct display
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_launch.log 2>&1 &"

# Wait for window to appear (JASP can be slow to start)
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 5. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 6. Capture initial state screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="