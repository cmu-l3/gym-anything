#!/bin/bash
set -e
echo "=== Setting up Factorial ANOVA task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists
DATASET_SOURCE="/opt/jamovi_datasets/ToothGrowth.csv"
DATASET_DEST="/home/ga/Documents/Jamovi/ToothGrowth.csv"

mkdir -p /home/ga/Documents/Jamovi
if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    echo "Dataset copied to $DATASET_DEST"
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    exit 1
fi

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi with the dataset loaded
# Using setsid to detach from the shell so it persists
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET_DEST' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ToothGrowth"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Wait a bit longer for UI to settle
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (sometimes appear on first run)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="