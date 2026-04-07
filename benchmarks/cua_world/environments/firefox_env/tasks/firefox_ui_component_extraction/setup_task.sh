#!/bin/bash
echo "=== Setting up Firefox UI Component Extraction task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state (remove any artifacts from previous runs)
rm -rf /home/ga/Documents/UI_Analysis
pkill -f firefox
sleep 2

# Target Wayback Machine URL
TARGET_URL="https://web.archive.org/web/20230921054336/https://developer.mozilla.org/en-US/"

# Start Firefox and navigate to the target URL
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox '$TARGET_URL' &"

# Wait for the window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Give page some time to load
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take an initial screenshot to prove starting state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="