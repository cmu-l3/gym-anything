#!/bin/bash
echo "=== Setting up personality_age_regression_diagnostics task ==="

# Kill any running Jamovi instance first
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    if [ -f "/opt/jamovi_datasets/BFI25.csv" ]; then
        cp "/opt/jamovi_datasets/BFI25.csv" "$DATASET"
    elif [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
    fi
fi

if [ ! -f "$DATASET" ]; then
    echo "ERROR: Dataset $DATASET not found."
    exit 1
fi
chown ga:ga "$DATASET"
echo "Dataset ready: $DATASET"

# Clean up any previous run artifacts BEFORE recording timestamp
rm -f "/home/ga/Documents/Jamovi/Personality_Age.omv"
rm -f "/home/ga/Documents/Jamovi/age_analysis_report.txt"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch Jamovi with the dataset pre-loaded
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Wait for UI to be fully responsive
sleep 15

# Dismiss any startup dialogs (welcome screen, update notifier)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 1

# Maximize the Jamovi window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -i "jamovi" | head -n 1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Maximizing window $WINDOW_ID..."
    DISPLAY=:1 wmctrl -ir "$WINDOW_ID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WINDOW_ID"
fi

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
