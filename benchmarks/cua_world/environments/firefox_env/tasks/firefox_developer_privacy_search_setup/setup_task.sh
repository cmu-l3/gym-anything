#!/bin/bash
echo "=== Setting up Firefox Developer Privacy & Search Setup Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing Firefox processes to ensure a clean slate
pkill -f firefox 2>/dev/null || true
sleep 2

# Clean existing places.sqlite to ensure no leftover keywords/bookmarks from previous tasks
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
if [ -d "$PROFILE_DIR" ]; then
    rm -f "$PROFILE_DIR/places.sqlite"* 2>/dev/null || true
fi

# Start Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox > /dev/null 2>&1 &"

# Wait for the Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Give it a moment to initialize the UI
sleep 3

# Maximize and focus the Firefox window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take an initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
fi

echo "=== Setup complete ==="