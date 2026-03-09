#!/bin/bash
set -e
echo "=== Setting up Kruskal-Wallis Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the data file exists in the user's documents
DATA_FILE="/home/ga/Documents/Jamovi/InsectSprays.csv"
if [ ! -f "$DATA_FILE" ]; then
    echo "Restoring InsectSprays.csv..."
    cp "/opt/jamovi_datasets/InsectSprays.csv" "$DATA_FILE"
    chown ga:ga "$DATA_FILE"
fi

# Clean up previous run artifacts
rm -f "/home/ga/Documents/Jamovi/InsectSprays_KruskalWallis.omv"
rm -f "/home/ga/Documents/Jamovi/kruskal_wallis_report.txt"

# Kill any running Jamovi instances to ensure fresh start
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi (empty state)
# We use the system-wide launcher script created in env setup
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_launch.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Wait a bit for UI to fully load
sleep 10

# Maximize the window
# Note: The window title might be "jamovi" or "Untitled"
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any "Welcome" or "What's New" dialogs if they appear
# Pressing Escape usually closes these overlays
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="