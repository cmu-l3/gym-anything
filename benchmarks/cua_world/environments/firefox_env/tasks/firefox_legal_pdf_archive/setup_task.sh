#!/bin/bash
echo "=== Setting up Firefox PDF Archive Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
su - ga -c "mkdir -p /home/ga/Documents"

# Clean up any existing file that might interfere
rm -f "/home/ga/Documents/WCAG21_Archive.pdf"

# Clean up any previous task states
rm -f /tmp/task_result.json
rm -f /tmp/firefox_prefs.js

# Ensure Firefox is running and navigated to the target page
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'https://www.w3.org/TR/WCAG21/' > /dev/null 2>&1 &"
    sleep 5
else
    echo "Firefox is already running, opening target page in a new tab..."
    su - ga -c "DISPLAY=:1 firefox -new-tab 'https://www.w3.org/TR/WCAG21/' > /dev/null 2>&1 &"
    sleep 3
fi

# Wait for Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize and focus the active Firefox window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait a moment for the page to render
sleep 3

# Take initial state screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="