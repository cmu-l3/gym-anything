#!/bin/bash
set -e
echo "=== Setting up Irrigation Pivot Layout Task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean up workspace
mkdir -p /home/ga/Documents/LibreCAD
rm -f /home/ga/Documents/LibreCAD/irrigation_layout.dxf
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Start LibreCAD
if ! pgrep -f "librecad" > /dev/null; then
    echo "Starting LibreCAD..."
    su - ga -c "DISPLAY=:1 librecad > /dev/null 2>&1 &"
    sleep 5
fi

# 4. Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 5. Dismiss any startup dialogs (Esc/Enter)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# 6. Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 8. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="