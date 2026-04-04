#!/bin/bash
set -e
echo "=== Setting up ANCOVA Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f "/home/ga/Documents/JASP/ExamAnxiety_ANCOVA.jasp"
rm -f "/home/ga/Documents/JASP/ancova_report.txt"
rm -f /tmp/task_result.json

# 3. Ensure dataset exists
DATASET_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"

mkdir -p "$(dirname "$DATASET_DEST")"

if [ ! -f "$DATASET_DEST" ]; then
    if [ -f "$DATASET_SOURCE" ]; then
        echo "Copying dataset..."
        cp "$DATASET_SOURCE" "$DATASET_DEST"
    else
        echo "ERROR: Source dataset not found at $DATASET_SOURCE"
        # Fallback download if local copy missing (redundancy)
        wget -q -O "$DATASET_DEST" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Exam%20Anxiety.csv"
    fi
fi
chown ga:ga "$DATASET_DEST"

# 4. Start JASP with the dataset
# We use setsid to detach from the shell so it survives
# We use the launcher script which handles flags
echo "Starting JASP..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET_DEST\" > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP" > /dev/null; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss "Check for Updates" or other dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="