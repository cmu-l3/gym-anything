#!/bin/bash
echo "=== Setting up independent_samples_t_test task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/InvisibilityCloak.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/Invisibility Cloak.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"

# Open Jamovi with the Invisibility Cloak dataset pre-loaded.
su - ga -c "setsid /usr/local/bin/launch-jamovi $DATASET > /tmp/jamovi_task.log 2>&1 &"
sleep 20

# Dismiss any lingering dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the Jamovi window (title is the filename, not "jamovi"; use :ACTIVE: to match current window)
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== independent_samples_t_test task setup complete ==="
