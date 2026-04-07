#!/bin/bash
# Setup for Custom Dashboard Start Page task

set -e

echo "=== Setting up custom_dashboard_startpage ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill Edge to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. Clean up previous run artifacts
TARGET_FILE="/home/ga/Desktop/travel_dashboard.html"
if [ -f "$TARGET_FILE" ]; then
    echo "Removing existing dashboard file..."
    rm -f "$TARGET_FILE"
fi

# 3. Reset Edge Preferences to default (Startup = New Tab)
# We want to ensure the agent actually changes this
PREFS_DIR="/home/ga/.config/microsoft-edge/Default"
PREFS_FILE="$PREFS_DIR/Preferences"

if [ -f "$PREFS_FILE" ]; then
    echo "Resetting Edge startup preferences..."
    # Python script to safely modify JSON
    python3 << PYEOF
import json
import os

try:
    with open("$PREFS_FILE", "r") as f:
        prefs = json.load(f)
    
    # Reset session startup to "Open the New Tab page" (5)
    if "session" not in prefs:
        prefs["session"] = {}
    prefs["session"]["restore_on_startup"] = 5
    prefs["session"]["startup_urls"] = []
    
    # Reset homepage just in case
    prefs["homepage"] = "about:blank"
    prefs["homepage_is_newtabpage"] = False

    with open("$PREFS_FILE", "w") as f:
        json.dump(prefs, f)
    print("Preferences reset successfully.")
except Exception as e:
    print(f"Error resetting preferences: {e}")
PYEOF
fi

# 4. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Edge (Blank start)
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="