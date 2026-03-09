#!/bin/bash
echo "=== Setting up insect_nonparametric task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the InsectSprays dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/InsectSprays.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/InsectSprays.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# Validate the dataset
DATASET_SIZE=$(stat -c%s "$DATASET" 2>/dev/null || echo 0)
if [ "$DATASET_SIZE" -lt 100 ]; then
    echo "ERROR: InsectSprays.csv is too small or missing (${DATASET_SIZE} bytes)"
    exit 1
fi
echo "Dataset ready: $DATASET (${DATASET_SIZE} bytes)"
head -3 "$DATASET"

# Record baseline state for verifier (no .omv should exist yet)
echo "$(date +%s)" > /tmp/task_start_timestamp
rm -f /home/ga/Documents/Jamovi/InsectSprayAnalysis.omv
ls -la /home/ga/Documents/Jamovi/ > /tmp/task_baseline_files.txt 2>/dev/null || true

# Open Jamovi with the InsectSprays dataset pre-loaded
su - ga -c "setsid /usr/local/bin/launch-jamovi $DATASET > /tmp/jamovi_task.log 2>&1 &"
sleep 20

# Dismiss any lingering dialogs (update notifier, welcome screen)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the Jamovi window (title is the filename, not "jamovi"; use :ACTIVE: to match current window)
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_screenshot.png" 2>/dev/null || true

echo "=== insect_nonparametric task setup complete ==="
