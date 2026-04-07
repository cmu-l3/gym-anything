#!/bin/bash
# setup_task.sh - Prepare environment for Cookie Injection task
set -e

echo "=== Setting up Cookie Injection Debug Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running Edge instances to ensure clean start
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

# Clean up previous output file
rm -f /home/ga/Desktop/cookie_verification.json

# Clean up Edge cookies database to start with a fresh state
# This prevents pre-existing cookies from confusing verification
COOKIES_DB="/home/ga/.config/microsoft-edge/Default/Cookies"
if [ -f "$COOKIES_DB" ]; then
    echo "Clearing existing cookies..."
    rm -f "$COOKIES_DB"
fi

# Launch Microsoft Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --disable-save-password-bubble \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge window to appear
echo "Waiting for Edge to start..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="