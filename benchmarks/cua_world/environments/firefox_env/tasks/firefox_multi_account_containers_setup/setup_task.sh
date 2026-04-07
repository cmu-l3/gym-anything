#!/bin/bash
echo "=== Setting up Firefox Multi-Account Containers Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"

# Ensure clean start state
pkill -f firefox 2>/dev/null || true
sleep 2

# Remove any existing custom containers to ensure agent must create them
if [ -f "$PROFILE_DIR/containers.json" ]; then
    rm -f "$PROFILE_DIR/containers.json"
fi

# Clear session store to avoid stale tabs
rm -rf "$PROFILE_DIR/sessionstore-backups/" 2>/dev/null || true
rm -f "$PROFILE_DIR/sessionstore.jsonlz4" 2>/dev/null || true

# Start Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox about:blank > /tmp/firefox_launch.log 2>&1 &"

# Wait for Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Allow time for profile initialization
sleep 3

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Dismiss any stray popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial state screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="