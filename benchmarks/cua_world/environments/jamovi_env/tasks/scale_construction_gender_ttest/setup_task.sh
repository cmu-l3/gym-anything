#!/bin/bash
set -e
echo "=== Setting up scale_construction_gender_ttest task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the dataset exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from source..."
    cp "/opt/jamovi_datasets/BFI25.csv" "$DATASET" 2>/dev/null || \
    python3 /opt/jamovi_datasets/extract_bfi25.py || \
    echo "ERROR: Could not generate BFI25.csv"
    chown ga:ga "$DATASET"
fi

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Launch Jamovi with the dataset
echo "Launching Jamovi with $DATASET..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi.log 2>&1 &"

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the window (using the window title which usually contains the filename)
sleep 5
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs (like 'Welcome')
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="