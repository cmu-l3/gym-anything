#!/bin/bash
echo "=== Setting up personality_efa task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the BFI25 dataset exists (extract from bfi.csv if missing)
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "BFI25.csv not found, extracting from bfi dataset..."
    mkdir -p /home/ga/Documents/Jamovi

    # First ensure bfi.csv is available (download if needed)
    if [ ! -f "/opt/jamovi_datasets/bfi.csv" ]; then
        echo "Downloading bfi.csv..."
        python3 -c "
import urllib.request
urllib.request.urlretrieve(
    'https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/psych/bfi.csv',
    '/opt/jamovi_datasets/bfi.csv'
)
print('bfi.csv downloaded')
"
    fi

    python3 /opt/jamovi_datasets/extract_bfi25.py
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"
wc -l "$DATASET"

# Record baseline state (no .omv file should exist yet)
OMV_PATH="/home/ga/Documents/Jamovi/BFI_FactorAnalysis.omv"
if [ -f "$OMV_PATH" ]; then
    echo "Warning: removing pre-existing .omv file from previous run"
    rm -f "$OMV_PATH"
fi
echo "Baseline: no .omv file at $OMV_PATH"
date +%s > /tmp/personality_efa_start_timestamp

# Open Jamovi with the BFI25 dataset pre-loaded
su - ga -c "setsid /usr/local/bin/launch-jamovi $DATASET > /tmp/jamovi_task.log 2>&1 &"
sleep 20

# Dismiss any lingering dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the Jamovi window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take a screenshot of the initial state
SCREENSHOT="/tmp/personality_efa_setup_screenshot.png"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT'" 2>/dev/null || true
if [ -f "$SCREENSHOT" ]; then
    echo "Setup screenshot saved: $SCREENSHOT"
else
    echo "Warning: Could not capture setup screenshot"
fi

echo "=== personality_efa task setup complete ==="
