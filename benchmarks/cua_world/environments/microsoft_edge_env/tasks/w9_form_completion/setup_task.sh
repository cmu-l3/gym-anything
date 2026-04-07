#!/bin/bash
# Setup for W-9 Form Completion task

set -e

echo "=== Setting up W-9 Form Completion Task ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Install pypdf for verification (in export_result.sh)
echo "Installing pypdf for validation..."
pip3 install pypdf --break-system-packages > /dev/null 2>&1 || true

# 2. Clean up previous artifacts
echo "Cleaning up previous run artifacts..."
rm -f "/home/ga/Documents/Acme_W9_Filled.pdf"
rm -f "/tmp/w9_task_result.json"

# 3. Ensure download directory exists
mkdir -p "/home/ga/Downloads"
mkdir -p "/home/ga/Documents"
chown -R ga:ga "/home/ga/Downloads" "/home/ga/Documents"

# 4. Kill existing Edge instances
echo "Killing existing Edge instances..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch Microsoft Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge to appear
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="