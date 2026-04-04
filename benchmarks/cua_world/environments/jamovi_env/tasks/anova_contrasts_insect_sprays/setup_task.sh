#!/bin/bash
set -e
echo "=== Setting up ANOVA Contrasts Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source directory for datasets
DATA_SOURCE="/opt/jamovi_datasets/InsectSprays.csv"
WORK_DIR="/home/ga/Documents/Jamovi"
TARGET_FILE="$WORK_DIR/InsectSprays.csv"

# Ensure clean state
pkill -f "org.jamovi.jamovi" || true
pkill -f "jamovi" || true
pkill -f "zygote" || true
sleep 2

# Prepare workspace
mkdir -p "$WORK_DIR"
chown ga:ga "$WORK_DIR"

# Ensure dataset exists
if [ ! -f "$TARGET_FILE" ]; then
    if [ -f "$DATA_SOURCE" ]; then
        cp "$DATA_SOURCE" "$TARGET_FILE"
        echo "Copied dataset to workspace."
    else
        echo "ERROR: Source dataset not found at $DATA_SOURCE"
        exit 1
    fi
fi
chown ga:ga "$TARGET_FILE"

# Launch Jamovi with the dataset
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$TARGET_FILE' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..50}; do
    if DISPLAY=:1 wmctrl -l | grep -i "InsectSprays"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Wait for UI to settle
sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="