#!/bin/bash
set -e
echo "=== Setting up partial_correlation_exam task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define paths
DATASET_SOURCE="/opt/jamovi_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

# Ensure clean state for output files
rm -f "/home/ga/Documents/Jamovi/ExamAnxiety_PartialCorr.omv"
rm -f "/home/ga/Documents/Jamovi/partial_correlation_report.txt"

# Ensure the dataset exists with the correct name (no spaces)
mkdir -p /home/ga/Documents/Jamovi
if [ ! -f "$DATASET_DEST" ]; then
    echo "Copying dataset from source..."
    cp "$DATASET_SOURCE" "$DATASET_DEST" || echo "Warning: Source dataset not found, checking alternative..."
fi
# Fallback check
if [ ! -f "$DATASET_DEST" ]; then
    echo "ERROR: Dataset not found at $DATASET_DEST"
    exit 1
fi
chown ga:ga "$DATASET_DEST"
chmod 644 "$DATASET_DEST"

echo "Dataset ready: $DATASET_DEST"

# Check if Jamovi is already running; if so, kill it to ensure fresh state
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi with the dataset
# Using setsid to detach from shell, running as user ga
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET_DEST' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Maximize the window
# Note: Jamovi window title usually reflects the filename
sleep 2
DISPLAY=:1 wmctrl -r "ExamAnxiety" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ExamAnxiety" 2>/dev/null || true

# Dismiss any potential "Welcome" or "Update" dialogs if they steal focus
# Pressing Escape usually closes them
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="