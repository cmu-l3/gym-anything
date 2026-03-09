#!/bin/bash
echo "=== Setting up descriptive_statistics task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/Sleep.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/Sleep.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"

# Open Jamovi with the Sleep dataset pre-loaded.
# Uses setsid so the process survives when su exits.
# --no-sandbox and --disable-gpu are set inside the launcher script.
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

echo "=== descriptive_statistics task setup complete ==="
