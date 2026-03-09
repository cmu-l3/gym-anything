#!/bin/bash
set -e
echo "=== Setting up Skate Ramp Profile Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Kill any running LibreCAD instances to ensure a fresh start
pkill -f librecad 2>/dev/null || true
sleep 2

# 3. Clean up previous artifacts
OUTPUT_FILE="/home/ga/Documents/LibreCAD/quarter_pipe.dxf"
rm -f "$OUTPUT_FILE"
mkdir -p "$(dirname "$OUTPUT_FILE")"
chown -R ga:ga "$(dirname "$OUTPUT_FILE")"

# 4. Start LibreCAD with a blank drawing
# We do not load a file; the agent must start from scratch (default new drawing)
if ! pgrep -f "librecad" > /dev/null; then
    echo "Starting LibreCAD..."
    su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"
fi

# 5. Wait for window to appear
echo "Waiting for LibreCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 6. Maximize the window (CRITICAL for visibility)
# Use both window name variants to be safe
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "unnamed" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 8. Dismiss potential "Tip of the Day" or startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="