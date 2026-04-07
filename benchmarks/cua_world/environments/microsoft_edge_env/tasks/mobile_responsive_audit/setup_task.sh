#!/bin/bash
# setup_task.sh - Pre-task hook for mobile_responsive_audit
# Sets up a clean Edge environment and ensures Desktop is clear

set -e

echo "=== Setting up mobile_responsive_audit task ==="

# 1. Kill any existing Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. Clean up Desktop and Downloads (remove previous attempts)
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/energy_mobile_audit.png
rm -f /home/ga/Downloads/*.png
rm -f /home/ga/Downloads/*.jpg
rm -f /home/ga/Downloads/*.jpeg

# 3. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 4. Launch Edge
echo "Launching Microsoft Edge..."
# Launch with basic flags; we want the agent to open DevTools manually
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    about:blank > /tmp/edge.log 2>&1 &"

# 5. Wait for Edge window
echo "Waiting for Edge to start..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected"
        break
    fi
    sleep 1
done

# 6. Ensure window is maximized
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="