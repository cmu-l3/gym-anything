#!/bin/bash
echo "=== Setting up IMAP provision task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# Start application if not running
if ! is_thunderbird_running; then
    start_thunderbird
    sleep 5
fi

# Wait for window
wait_for_thunderbird_window 30

# Maximize and focus Thunderbird
maximize_thunderbird

# Click center of desktop to ensure nothing is blocking and Thunderbird is active
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1
maximize_thunderbird

# Take initial screenshot showing clean starting state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="