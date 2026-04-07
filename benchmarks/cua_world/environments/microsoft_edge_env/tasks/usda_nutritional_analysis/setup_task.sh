#!/bin/bash
# Setup for USDA Nutritional Analysis task

set -e
echo "=== Setting up USDA Nutritional Analysis Task ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Kill any existing Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. Clean up artifacts from previous runs
rm -f /home/ga/Documents/nutrition_report.txt
# Clean Downloads to easily detect new files
rm -rf /home/ga/Downloads/*

# 3. Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads
chown -R ga:ga /home/ga/Documents /home/ga/Downloads

# 4. Launch Edge
echo "Launching Microsoft Edge..."
# Launch with flags to minimize popups/first-run experiences
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    > /tmp/edge_launch.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 6. Maximize window explicitly
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="