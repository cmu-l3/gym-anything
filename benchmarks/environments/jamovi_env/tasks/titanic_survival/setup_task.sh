#!/bin/bash
echo "=== Setting up titanic_survival task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/TitanicSurvival.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/TitanicSurvival.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"
wc -l "$DATASET"

# Record baseline state — no .omv file should exist yet
OMV_PATH="/home/ga/Documents/Jamovi/TitanicAnalysis.omv"
rm -f "$OMV_PATH" 2>/dev/null || true
date +%s > /tmp/titanic_survival_task_start_ts
echo "Baseline: no .omv file, timestamp recorded"

# Open Jamovi with the TitanicSurvival dataset pre-loaded
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

# Take a baseline screenshot
SCREENSHOT="/tmp/titanic_survival_baseline.png"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT'" 2>/dev/null || true
if [ -f "$SCREENSHOT" ]; then
    echo "Baseline screenshot saved: $SCREENSHOT"
else
    echo "Warning: Could not capture baseline screenshot"
fi

echo "=== titanic_survival task setup complete ==="
