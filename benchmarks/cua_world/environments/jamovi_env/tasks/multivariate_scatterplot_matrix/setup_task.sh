#!/bin/bash
set -e
echo "=== Setting up multivariate_scatterplot_matrix task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Ensure the dataset exists
DATASET_SOURCE="/opt/jamovi_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

# Handle potential naming differences from environment setup
if [ ! -f "$DATASET_DEST" ]; then
    if [ -f "$DATASET_SOURCE" ]; then
        echo "Copying dataset from $DATASET_SOURCE..."
        mkdir -p /home/ga/Documents/Jamovi
        cp "$DATASET_SOURCE" "$DATASET_DEST"
        chown ga:ga "$DATASET_DEST"
    elif [ -f "/home/ga/Documents/Jamovi/Exam Anxiety.csv" ]; then
        # If it exists with spaces, copy to no-space version for safety
        cp "/home/ga/Documents/Jamovi/Exam Anxiety.csv" "$DATASET_DEST"
    else
        echo "ERROR: Dataset not found!"
        exit 1
    fi
fi

echo "Dataset ready: $DATASET_DEST"

# Remove any previous result file
rm -f "/home/ga/Documents/Jamovi/ExamAnxiety_Matrix.omv"

# Open Jamovi with the dataset loaded
# Using setsid to detach from shell, avoiding hang on su
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET_DEST' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi" > /dev/null; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Wait a bit for UI to settle
sleep 5

# Maximize the window (finding it by the dataset name usually works best in Jamovi)
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Fallback to class name if title match fails
DISPLAY=:1 wmctrl -x -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="