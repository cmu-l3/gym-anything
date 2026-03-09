#!/bin/bash
set -e
echo "=== Setting up equivalence_test_toothgrowth task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists and has correct permissions
DATASET="/home/ga/Documents/JASP/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset..."
    cp "/opt/jasp_datasets/Tooth Growth.csv" "$DATASET"
fi
chown ga:ga "$DATASET"
chmod 644 "$DATASET"

# 3. Clean up any previous output
rm -f "/home/ga/Documents/JASP/Bioequivalence.jasp"

# 4. Launch JASP with dataset
# Using setsid so it survives shell exit, and proper flags for container
echo "Launching JASP..."
pkill -f "JASP" 2>/dev/null || true
sleep 2

su - ga -c "setsid /usr/local/bin/launch-jasp '$DATASET' > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done
sleep 5 # Allow UI to render

# 6. Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Dismiss "Check for Updates" or welcome dialogs if they appear
# Press Escape a couple of times just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="