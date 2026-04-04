#!/bin/bash
echo "=== Setting up lmm_sleep_analysis task ==="

# 1. Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f /home/ga/Documents/JASP/Sleep_LMM.jasp
rm -f /home/ga/Documents/JASP/lmm_report.txt
rm -f /tmp/task_result.json

# 3. Ensure dataset exists
DATASET="/home/ga/Documents/JASP/Sleep.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying Sleep dataset..."
    mkdir -p /home/ga/Documents/JASP
    cp "/opt/jasp_datasets/Sleep.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 4. Launch JASP with the dataset
# Using setsid to ensure it survives when the shell exits
# QTWEBENGINE_CHROMIUM_FLAGS is handled by the wrapper script /usr/local/bin/launch-jasp
echo "Launching JASP..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET\" > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and focus
sleep 5 # Allow UI to render
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss "Check for Updates" or welcome dialogs if they appear
# Press Escape a couple of times
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true

# 8. Initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="