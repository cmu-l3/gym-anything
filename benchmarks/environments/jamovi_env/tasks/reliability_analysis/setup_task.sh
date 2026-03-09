#!/bin/bash
echo "=== Setting up reliability_analysis task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the NeuroticiIndex dataset exists (generate if missing)
DATASET="/home/ga/Documents/Jamovi/NeuroticiIndex.csv"
if [ ! -f "$DATASET" ]; then
    echo "Extracting NeuroticiIndex.csv from real bfi dataset..."
    mkdir -p /home/ga/Documents/Jamovi
    python3 /opt/jamovi_datasets/extract_bfi_neuroticism.py
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"

# Open Jamovi with the NeuroticiIndex dataset pre-loaded.
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

echo "=== reliability_analysis task setup complete ==="
