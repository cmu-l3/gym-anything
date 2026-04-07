#!/bin/bash
echo "=== Setting up foundation_footing_layout task ==="

# Source utilities safely
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    echo "task_utils.sh not found, continuing without it"
fi

# 1. Ensure output directory exists and is clean
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects
rm -f /home/ga/BIMProjects/foundation_layout.ifc 2>/dev/null || true

# 2. Kill any existing Blender instances
pkill -f "/opt/blender/blender" 2>/dev/null || true
sleep 2

# 3. Record task start timestamp (crucial for anti-gaming)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 4. Launch Blender (empty session for a new project)
echo "Launching Blender (empty session for new foundation project)..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window to appear
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 15 ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "blender" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Blender window detected: $WID"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Extra time for Bonsai to initialize
sleep 5

# 5. Maximize window, dismiss splash, and screenshot
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 1
# Dismiss splash screen
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1
# Ensure it's active again
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Capture initial state
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Blender launched with empty session."
echo "Expected output: /home/ga/BIMProjects/foundation_layout.ifc"