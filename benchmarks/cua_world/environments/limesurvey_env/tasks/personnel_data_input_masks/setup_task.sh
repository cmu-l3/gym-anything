#!/bin/bash
echo "=== Setting up Personnel Data Input Masks task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready (health check)
echo "Checking LimeSurvey availability..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Ensure Firefox is not running from a previous session
pkill -f firefox 2>/dev/null || true

# Start Firefox pointing to LimeSurvey admin
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="