#!/bin/bash
set -e
echo "=== Setting up One Sample T-Test Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure data exists (redundancy check)
DATA_FILE="/home/ga/Documents/Jamovi/ToothGrowth.csv"
if [ ! -f "$DATA_FILE" ]; then
    echo "Restoring ToothGrowth.csv..."
    cp "/opt/jamovi_datasets/ToothGrowth.csv" "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Clean up previous outputs
rm -f "/home/ga/Documents/Jamovi/OneSampleTTest_ToothGrowth.omv"

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (Empty)
# We launch it empty because the task description explicitly asks the agent to Open the file.
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for window
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss welcome dialog if present (Esc, then Enter usually works)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Ensure maximized again
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="