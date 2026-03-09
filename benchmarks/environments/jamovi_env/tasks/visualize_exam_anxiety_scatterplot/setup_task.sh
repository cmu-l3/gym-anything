#!/bin/bash
set -e
echo "=== Setting up Visualize Exam Anxiety Scatterplot task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists
DATASET_SOURCE="/opt/jamovi_datasets/Exam Anxiety.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

mkdir -p "$(dirname "$DATASET_DEST")"

if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    # Ensure ownership is correct so agent can read/write
    chown ga:ga "$DATASET_DEST"
    chmod 644 "$DATASET_DEST"
    echo "Dataset prepared at $DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    exit 1
fi

# 3. Clean up previous runs
rm -f "/home/ga/Documents/Jamovi/ExamScatterplot.omv"
rm -f /tmp/task_result.json

# 4. Start Jamovi (Clean State - No file open initially, per task description)
# The agent must open the file themselves.
if ! pgrep -f "org.jamovi.jamovi" > /dev/null; then
    echo "Starting Jamovi..."
    # Launch without a file argument
    su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"
    
    # Wait for window to appear
    echo "Waiting for Jamovi window..."
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
            echo "Jamovi window detected."
            break
        fi
        sleep 1
    done
    sleep 5 # Allow UI to render
else
    echo "Jamovi is already running."
fi

# 5. Maximize and Focus
# Jamovi window title often matches the open file or just "jamovi"
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="