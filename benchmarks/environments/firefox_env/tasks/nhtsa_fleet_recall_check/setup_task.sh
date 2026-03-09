#!/bin/bash
# setup_task.sh - Pre-task hook for nhtsa_fleet_recall_check

set -e
echo "=== Setting up NHTSA Fleet Recall Check task ==="

# 1. Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# 2. Ensure clean environment
# Kill any running Firefox instances
pkill -u ga -f firefox 2>/dev/null || true
sleep 1
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# Remove any previous report file
rm -f /home/ga/Documents/fleet_recall_report.json

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 3. Locate Firefox profile (for logging purposes, actual DB work happens in export)
PROFILE_DIR=""
# Check snap location first (common in Ubuntu)
if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox" ]; then
    PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox -name "*.default*" | head -n 1)
fi
# Check standard location if not found
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find /home/ga/.mozilla/firefox -name "*.default*" | head -n 1)
fi
echo "Firefox profile found at: $PROFILE_DIR"
echo "$PROFILE_DIR" > /tmp/firefox_profile_path.txt

# 4. Launch Firefox to a blank page to ensure it's ready for the agent
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox --no-remote about:blank > /dev/null 2>&1 &"

# Wait for window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="