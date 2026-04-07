#!/bin/bash
echo "=== Setting up Firefox TLS Cert Export Task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure the Downloads directory exists and is clean of old certs
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/*.pem
rm -f /home/ga/Downloads/*.crt
rm -f /tmp/task_result.json

# Ensure Firefox is running
if ! pgrep -u ga -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox about:blank &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Give the UI a moment to stabilize
sleep 2

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="