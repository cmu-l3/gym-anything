#!/bin/bash
set -euo pipefail

echo "=== Setting up OpenPGP configuration task ==="

# Source shared utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs or fake files
rm -f /home/ga/Documents/testuser_pubkey.asc 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Start Thunderbird if not already running
if ! pgrep -f "thunderbird" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &" 2>/dev/null
    sleep 8
fi

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -qi "Mozilla Thunderbird"; then
        break
    fi
    sleep 1
done

# Focus and maximize the Thunderbird window
WID=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "Mozilla Thunderbird" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
fi

# Ensure we are on the main window by closing any existing Account Settings dialogs
su - ga -c "DISPLAY=:1 wmctrl -c 'Account Settings' 2>/dev/null" || true
su - ga -c "DISPLAY=:1 wmctrl -c 'OpenPGP Key Manager' 2>/dev/null" || true
sleep 1

# Take initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="