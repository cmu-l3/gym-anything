#!/bin/bash
set -e
echo "=== Setting up Moderated Regression Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jamovi is not running initially
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# 3. Clean up previous artifacts
rm -f /home/ga/Documents/Jamovi/ToothGrowth_Moderated.omv
rm -f /home/ga/Documents/Jamovi/moderated_regression_results.txt
rm -f /tmp/task_result.json

# 4. Ensure the dataset exists and is clean
DATASET="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATASET" ]; then
    echo "Restoring ToothGrowth.csv..."
    mkdir -p /home/ga/Documents/Jamovi
    # Try to copy from system location if available, otherwise assume it's there from environment setup
    if [ -f "/opt/jamovi_datasets/ToothGrowth.csv" ]; then
        cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATASET"
    fi
fi
# Set permissions
chown ga:ga "$DATASET"
chmod 644 "$DATASET"

# 5. Launch Jamovi (Empty state)
# Using setsid to detach from the shell so it persists
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for Jamovi window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window found."
        break
    fi
    sleep 1
done

# 7. Maximize the window (Critical for VLM visibility)
# Wait a bit for the UI to fully render
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Also try matching by class if title fails
DISPLAY=:1 wmctrl -x -r "jamovi.Jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Focus the window
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 9. Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="