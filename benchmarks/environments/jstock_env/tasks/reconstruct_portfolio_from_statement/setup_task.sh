#!/bin/bash
set -e
echo "=== Setting up Reconstruct Portfolio Task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
# Remove the "Recovery" portfolio if it exists to ensure a clean slate
RECOVERY_DIR="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Recovery"
if [ -d "$RECOVERY_DIR" ]; then
    echo "Removing existing Recovery portfolio..."
    rm -rf "$RECOVERY_DIR"
fi

# 3. Ensure JStock is not running
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 4. Launch JStock
echo "Launching JStock..."
# Using setsid to detach from shell, redirecting output
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 5. Wait for application window
echo "Waiting for JStock to appear..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window found."
        break
    fi
    sleep 1
done

# 6. Handle startup dialogs (News)
# Give it a moment to fully render the dialog
sleep 5
# Press Enter to dismiss "JStock News" or "What's New"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
# Press Escape just in case
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true

# 7. Maximize and focus
echo "Maximizing window..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r 'JStock' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a 'JStock'" 2>/dev/null || true

# 8. Take initial screenshot
echo "Capturing initial state..."
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="