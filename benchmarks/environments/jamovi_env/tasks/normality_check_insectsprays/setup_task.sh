#!/bin/bash
set -e
echo "=== Setting up normality_check_insectsprays task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure dataset exists in the Documents folder
DATASET="/home/ga/Documents/Jamovi/InsectSprays.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/InsectSprays.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

# Clean up previous run artifacts
rm -f "/home/ga/Documents/Jamovi/analysis_decision.txt"
rm -f "/home/ga/Documents/Jamovi/InsectAnalysis.omv"

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Launch Jamovi (empty state, as required by task description)
# We launch it without a file argument so the agent has to open it.
echo "Starting Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for visibility)
# Wait a bit for the window to be fully realized
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any 'Welcome' or 'What's New' dialogs if they appear
# Usually Escape or Return works
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="