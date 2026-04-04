#!/bin/bash
set -e
echo "=== Setting up reliability_reverse_coded_extraversion task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Jamovi is not already running (clean slate)
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Ensure the BFI25 dataset exists
# It should be created by the environment setup, but we verify here
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"

if [ ! -f "$DATASET" ]; then
    echo "Regenerating BFI25 dataset..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
        # Move it to expected location if the script didn't put it there
        if [ ! -f "$DATASET" ] && [ -f "/home/ga/Documents/Jamovi/BFI25.csv" ]; then
             echo "Dataset found at expected location."
        elif [ -f "BFI25.csv" ]; then
             mv "BFI25.csv" "$DATASET"
        fi
    else
        echo "ERROR: Extraction script missing."
        exit 1
    fi
fi

# Set ownership
chown ga:ga "$DATASET"
chmod 644 "$DATASET"

# Launch Jamovi (empty)
echo "Launching Jamovi..."
# using setsid to detach from shell
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss welcome dialogs if any (Esc, Enter)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="