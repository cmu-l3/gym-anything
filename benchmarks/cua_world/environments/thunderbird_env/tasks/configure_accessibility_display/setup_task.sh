#!/bin/bash
set -euo pipefail
echo "=== Setting up Configure Accessibility Display task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Start Thunderbird if not running
if ! pgrep -f "thunderbird" > /dev/null 2>&1; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
    sleep 8
fi

# Wait for Thunderbird window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird" > /dev/null; then
        echo "Thunderbird window detected."
        break
    fi
    sleep 1
done

# Focus and maximize the window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Thunderbird" | awk '{print $1}' | head -1 || echo "")
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Ensure settings aren't already open
DISPLAY=:1 wmctrl -c "Settings" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== Task setup complete ==="