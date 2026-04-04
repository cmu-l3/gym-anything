#!/bin/bash
set -e
echo "=== Setting up Log-Linear Titanic Survival task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# Ensure permissions are correct
chmod 644 "$DATASET"

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi with the dataset
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi \"$DATASET\" > /tmp/jamovi_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "TitanicSurvival"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for agent visibility)
# Note: Jamovi window title usually matches the filename
DISPLAY=:1 wmctrl -r "TitanicSurvival" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "TitanicSurvival" 2>/dev/null || true

# Dismiss any startup dialogs (sometimes appear)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="