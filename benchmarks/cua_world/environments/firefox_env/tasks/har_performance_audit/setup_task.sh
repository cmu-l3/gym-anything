#!/bin/bash
echo "=== Setting up HAR Performance Audit task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any pre-existing files that would conflict with the task
rm -f /home/ga/Documents/jwst_network.har 2>/dev/null || true
rm -f /home/ga/Documents/slowest_asset.txt 2>/dev/null || true

# Kill any existing Firefox processes to ensure a clean slate
echo "Stopping any existing Firefox instances..."
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Start Firefox on a blank page
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox about:blank > /tmp/firefox_launch.log 2>&1 &"

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Mozilla Firefox"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize and focus the Firefox window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Give the UI a moment to settle
sleep 2

# Take initial screenshot to prove starting state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="