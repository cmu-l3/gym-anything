#!/bin/bash
echo "=== Setting up descriptive_statistics task ==="

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 3

# Ensure the dataset exists
DATASET="/home/ga/Documents/JASP/Sleep.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jasp_datasets..."
    mkdir -p /home/ga/Documents/JASP
    cp "/opt/jasp_datasets/Sleep.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"

# Open JASP with the Sleep dataset pre-loaded.
# Uses setsid so the process survives when su exits.
# QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox is set inside the launcher script.
su - ga -c "setsid /usr/local/bin/launch-jasp $DATASET > /tmp/jasp_task.log 2>&1 &"
sleep 22

# Dismiss any dialogs (e.g. check-for-updates dialog)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== descriptive_statistics task setup complete ==="
