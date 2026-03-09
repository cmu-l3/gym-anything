#!/bin/bash
set -e
echo "=== Setting up Regression Reference Level Task ==="

# 1. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Ensure dataset exists
DATASET="/home/ga/Documents/Jamovi/InsectSprays.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset from backup..."
    cp "/opt/jamovi_datasets/InsectSprays.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# 3. Clean up any previous run artifacts
rm -f "/home/ga/Documents/Jamovi/InsectSprays_Ref_F.omv"
rm -f "/home/ga/Documents/Jamovi/coefficients_report.txt"

# 4. Launch Jamovi with the dataset
# Using setsid to detach from the shell so it persists
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi_launch.log 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "InsectSprays"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Allow UI to fully load
sleep 15

# Maximize the window (CRITICAL for VLM and agent visibility)
# Note: Jamovi window title usually matches the filename
DISPLAY=:1 wmctrl -r "InsectSprays" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "InsectSprays" 2>/dev/null || true

# Dismiss "Welcome to Jamovi" or update dialogs if any appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture initial state screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="