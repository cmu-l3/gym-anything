#!/bin/bash
set -e
echo "=== Setting up ANCOVA Exam Performance task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean any previous task artifacts
rm -f /home/ga/Documents/Jamovi/ExamAnxiety_ANCOVA.omv 2>/dev/null || true

# Verify dataset exists in the user workspace
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring ExamAnxiety.csv..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi
echo "Dataset confirmed: $DATASET"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Launch Jamovi with ExamAnxiety.csv pre-loaded
echo "Launching Jamovi with dataset..."
# Uses setsid so the process survives when su exits
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi window to appear (Electron takes 10-20s)
echo "Waiting for Jamovi window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "jamovi"; then
        echo "Jamovi window detected after ${i}s"
        break
    fi
    sleep 1
done

# Additional wait for full UI initialization
sleep 5

# Maximize the window (CRITICAL for agent visibility)
# Note: Jamovi window title often reflects the filename, e.g., "ExamAnxiety"
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs if they appear (e.g. 'What's New')
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== ANCOVA task setup complete ==="