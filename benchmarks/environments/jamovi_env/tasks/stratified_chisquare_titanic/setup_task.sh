#!/bin/bash
set -e
echo "=== Setting up stratified_chisquare_titanic task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"

# Launch Jamovi (empty) - Agent must open the file
# Using setsid to detach from the shell
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi window
echo "Waiting for Jamovi to launch..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize the Jamovi window
# Note: The window title might be "jamovi" or "Untitled" initially
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Untitled" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="