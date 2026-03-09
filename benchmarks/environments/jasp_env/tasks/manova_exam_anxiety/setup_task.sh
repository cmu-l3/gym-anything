#!/bin/bash
set -e
echo "=== Setting up MANOVA Task ==="

# Source shared utilities if available, otherwise define minimal ones
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback timestamp
    date +%s > /tmp/task_start_time.txt
fi

# 1. Record Start Time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare Dataset
# Ensure the dataset exists (space-free filename to avoid quoting issues)
DATASET_SOURCE="/opt/jasp_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/JASP/ExamAnxiety.csv"
mkdir -p /home/ga/Documents/JASP

if [ ! -f "$DATASET_DEST" ]; then
    echo "Copying dataset..."
    cp "$DATASET_SOURCE" "$DATASET_DEST" || echo "Warning: Source dataset not found, checking backup..."
fi
# Ensure ownership
chown -R ga:ga /home/ga/Documents/JASP

# 3. Clean previous results
rm -f "/home/ga/Documents/JASP/ExamAnxiety_MANOVA.jasp" 2>/dev/null || true

# 4. Launch JASP
# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

echo "Launching JASP with dataset: $DATASET_DEST"
# Use setsid so the process survives when su exits
# QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox is set inside the launcher script
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET_DEST > /tmp/jasp_task.log 2>&1 &"

# 5. Wait for JASP to load (it's heavy)
echo "Waiting for JASP to load..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done
sleep 5 # Extra buffer for UI rendering

# 6. Maximize Window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 7. Dismiss any startup dialogs (like 'Check for Updates')
# Try escaping a few times just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="