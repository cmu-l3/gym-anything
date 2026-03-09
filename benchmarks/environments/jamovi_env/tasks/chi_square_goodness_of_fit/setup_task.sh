#!/bin/bash
set -e
echo "=== Setting up Chi-Square Goodness of Fit task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
DATA_DIR="/home/ga/Documents/Jamovi"
DATASET="$DATA_DIR/TitanicSurvival.csv"
OUTPUT_FILE="$DATA_DIR/TitanicGoF.omv"

# Ensure output directory exists
mkdir -p "$DATA_DIR"
chown ga:ga "$DATA_DIR"

# Clean up previous artifacts
rm -f "$OUTPUT_FILE"
rm -f /tmp/task_result.json

# Ensure the dataset exists
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    if [ -f "/opt/jamovi_datasets/TitanicSurvival.csv" ]; then
        cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
        chown ga:ga "$DATASET"
    else
        echo "ERROR: Source dataset not found!"
        exit 1
    fi
fi

echo "Dataset confirmed at: $DATASET"

# Kill any running Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (Empty - user must open file)
# Using setsid to detach from shell
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the window for visibility
echo "Maximizing window..."
sleep 2
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="