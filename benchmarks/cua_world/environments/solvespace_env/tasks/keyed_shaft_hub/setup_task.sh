#!/bin/bash
echo "=== Setting up Keyed Shaft Hub Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Clean any existing files to prevent gaming
rm -f /home/ga/Documents/SolveSpace/keyed_hub.slvs
rm -f /home/ga/Documents/SolveSpace/keyed_hub.stl

# Start SolveSpace
if ! pgrep -f "solvespace" > /dev/null; then
    echo "Starting SolveSpace..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority /usr/bin/solvespace &"
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "solvespace"; then
        echo "SolveSpace window detected"
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "SolveSpace" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "SolveSpace" 2>/dev/null || true

# Move Property Browser out of the way to ensure full visibility of the canvas
DISPLAY=:1 wmctrl -r "Property Browser" -e 0,1538,64,382,370 2>/dev/null || true

# Give UI time to settle
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Setup complete ==="