#!/bin/bash
set -e
echo "=== Setting up feature_engineering_correlation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running JASP instance
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
sleep 2

# Ensure the dataset exists
DATASET_SOURCE="/opt/jasp_datasets/Big Five Personality Traits.csv"
DATASET_DEST="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

mkdir -p /home/ga/Documents/JASP

if [ -f "$DATASET_SOURCE" ]; then
    cp "$DATASET_SOURCE" "$DATASET_DEST"
    chown ga:ga "$DATASET_DEST"
    echo "Dataset copied to workspace."
else
    echo "ERROR: Source dataset not found at $DATASET_SOURCE"
    exit 1
fi

# Clean up previous results if they exist
rm -f "/home/ga/Documents/JASP/PlasticityAnalysis.jasp"
rm -f "/home/ga/Documents/JASP/plasticity_report.txt"

# Open JASP with the dataset pre-loaded
# Uses setsid so the process survives when su exits
echo "Launching JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp \"$DATASET_DEST\" > /tmp/jasp_task.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any potential dialogs (Escape then Enter)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="