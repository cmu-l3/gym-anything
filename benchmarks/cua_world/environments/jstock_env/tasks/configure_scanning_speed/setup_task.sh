#!/bin/bash
set -e
echo "=== Setting up configure_scanning_speed task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance to ensure clean start
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# Launch JStock
# ============================================================
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to initialize
echo "Waiting for JStock window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done
# Extra sleep for Java Swing initialization
sleep 5

# Dismiss "JStock News" dialog if it appears (Enter key)
# This dialog often blocks the main UI on startup
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2

# Also try Escape just in case
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# Maximize the main window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus the window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

# Record initial config state if it exists (for debugging/comparison)
# JStock options are usually in ~/.jstock/1.0.7/config/options.xml or similar
FIND_OPTS=$(find /home/ga/.jstock -name "*option*.xml" | head -n 1)
if [ -n "$FIND_OPTS" ]; then
    cp "$FIND_OPTS" /tmp/initial_options.xml 2>/dev/null || true
fi

echo "=== Task setup complete ==="