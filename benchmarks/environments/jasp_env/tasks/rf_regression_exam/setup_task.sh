#!/bin/bash
set -e
echo "=== Setting up RF Regression Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f /home/ga/Documents/JASP/rf_exam_analysis.jasp
rm -f /home/ga/Documents/JASP/rf_report.txt
rm -f /tmp/task_result.json

# 3. Ensure dataset exists in Documents (standard location)
# The environment install script puts them there, but we double check
DATA_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATA_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"

if [ ! -f "$DATA_DEST" ]; then
    echo "Restoring dataset..."
    mkdir -p "$(dirname "$DATA_DEST")"
    cp "$DATA_SOURCE" "$DATA_DEST" 2>/dev/null || \
    wget -q -O "$DATA_DEST" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Exam%20Anxiety.csv"
    chown ga:ga "$DATA_DEST"
fi

# 4. Kill any stale JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# 5. Launch JASP with the dataset
# CRITICAL: Use setsid to detach from shell, otherwise JASP dies when script ends
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATA_DEST\" > /tmp/jasp_launch.log 2>&1 &"

# 6. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done
sleep 5 # Allow UI to fully render

# 7. Maximize the window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 8. Dismiss startup dialogs (e.g. "Welcome" or "Updates") if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="