#!/bin/bash
set -e
echo "=== Setting up Outlier Detection Task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f "/home/ga/Documents/JASP/OutlierAnalysis.jasp"
rm -f "/home/ga/Documents/JASP/outlier_report.txt"

# 3. Ensure Dataset Exists
DATASET_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"

mkdir -p "$(dirname "$DATASET_DEST")"

if [ ! -f "$DATASET_DEST" ]; then
    if [ -f "$DATASET_SOURCE" ]; then
        echo "Copying dataset..."
        cp "$DATASET_SOURCE" "$DATASET_DEST"
    else
        echo "ERROR: Source dataset not found at $DATASET_SOURCE"
        # Fallback download if missing (should be there from env setup, but safe to handle)
        wget -q -O "$DATASET_DEST" "https://raw.githubusercontent.com/jasp-stats/jasp-desktop/master/Resources/Data%20Sets/Data%20Library/4.%20Regression/Exam%20Anxiety.csv"
    fi
    chown ga:ga "$DATASET_DEST"
fi

# 4. Launch JASP
# We use the system-wide launcher wrapper which handles flags and setsid
echo "Launching JASP..."
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET_DEST\" > /tmp/jasp_launch.log 2>&1 &"

# 5. Wait for JASP window
echo "Waiting for JASP to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done
sleep 5 # Extra buffer for UI rendering

# 6. Maximize and Focus
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Dismiss "Check for Updates" or Welcome dialogs if they appear
# Usually handled by config, but good to be safe
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 8. Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="