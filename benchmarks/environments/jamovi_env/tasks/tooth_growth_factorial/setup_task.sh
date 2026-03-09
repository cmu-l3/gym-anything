#!/bin/bash
echo "=== Setting up tooth_growth_factorial task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# Validate dataset
if [ ! -f "$DATASET" ]; then
    echo "ERROR: Dataset not found at $DATASET"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 100 ]; then
    echo "ERROR: Dataset file too small (${FILE_SIZE} bytes)"
    exit 1
fi

echo "Dataset ready: $DATASET (${FILE_SIZE} bytes)"
echo "First 3 lines:"
head -3 "$DATASET"

# Record baseline: confirm no .omv output file exists yet
OMV_OUTPUT="/home/ga/Documents/Jamovi/ToothGrowthAnalysis.omv"
rm -f "$OMV_OUTPUT" 2>/dev/null || true
echo "Baseline: no .omv output file at $OMV_OUTPUT"

# Record task start timestamp
date +%s > /tmp/tooth_growth_factorial_task_start.ts
echo "Task start timestamp: $(cat /tmp/tooth_growth_factorial_task_start.ts)"

# Launch Jamovi with the ToothGrowth dataset pre-loaded.
# Uses setsid so the process survives when su exits.
echo "Launching Jamovi with ToothGrowth.csv..."
su - ga -c "setsid /usr/local/bin/launch-jamovi $DATASET > /tmp/jamovi_task.log 2>&1 &"
sleep 22

# Dismiss any lingering dialogs (update notifier, welcome screen)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the Jamovi window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take a screenshot of the initial state
SCREENSHOT_PATH="/tmp/tooth_growth_factorial_setup.png"
rm -f "$SCREENSHOT_PATH" 2>/dev/null || true
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT_PATH'" 2>/dev/null || true
if [ -f "$SCREENSHOT_PATH" ]; then
    echo "Setup screenshot saved: $SCREENSHOT_PATH"
else
    echo "Warning: Could not capture setup screenshot"
fi

echo "=== tooth_growth_factorial task setup complete ==="
