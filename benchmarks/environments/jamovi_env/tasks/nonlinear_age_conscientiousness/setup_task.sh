#!/bin/bash
set -e
echo "=== Setting up nonlinear_age_conscientiousness task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure BFI25.csv exists (it should be created by environment setup, but verifying)
DATA_PATH="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATA_PATH" ]; then
    echo "ERROR: $DATA_PATH not found. Attempting to regenerate..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
        chown ga:ga "$DATA_PATH"
    else
        echo "CRITICAL ERROR: Extraction script missing."
        exit 1
    fi
fi

# Clean up any previous run artifacts
rm -f /home/ga/Documents/Jamovi/Conscientiousness_NonLinear.omv
rm -f /home/ga/Documents/Jamovi/nonlinear_results.txt

# Launch Jamovi (empty state)
# We use setsid to ensure it survives the shell exit
echo "Launching Jamovi..."
pkill -f "org.jamovi.jamovi" || true
sleep 2
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi" > /dev/null; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Fallback for different window titles
DISPLAY=:1 wmctrl -r "Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any startup dialogs (Welcome screen)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="