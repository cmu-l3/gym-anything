#!/bin/bash
echo "=== Setting up Wikipedia Citation Capture Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Setup workspace and clean up any potential pre-existing files
mkdir -p /home/ga/Documents/Research
rm -f /home/ga/Documents/Research/apollo11.pdf 2>/dev/null || true
rm -f /home/ga/Documents/Research/apollo11.bib 2>/dev/null || true

# Clean up downloads directory to prevent confusion
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/*Apollo* 2>/dev/null || true
rm -f /home/ga/Downloads/*wikipedia* 2>/dev/null || true

# Stop any running Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 2

# Start Firefox cleanly
su - ga -c "DISPLAY=:1 firefox about:blank &"
sleep 5

# Wait for Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Mozilla Firefox"; then
        break
    fi
    sleep 1
done

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial state screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="