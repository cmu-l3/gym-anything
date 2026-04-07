#!/bin/bash
# setup_task.sh - Pre-task hook for high_res_asset_curation
set -e

echo "=== Setting up High-Res Asset Curation Task ==="

# 1. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up target directory to ensure fresh start
TARGET_DIR="/home/ga/Documents/LectureAssets"
if [ -d "$TARGET_DIR" ]; then
    echo "Cleaning up existing target directory..."
    rm -rf "$TARGET_DIR"
fi

# 3. Ensure Downloads folder exists and is empty of previous task artifacts
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/*

# 4. Launch Microsoft Edge to a blank page or Wikimedia Commons
echo "Launching Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --start-maximized \
    'https://commons.wikimedia.org' > /dev/null 2>&1 &"

# 5. Wait for browser window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# 6. Maximize window explicitly
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="