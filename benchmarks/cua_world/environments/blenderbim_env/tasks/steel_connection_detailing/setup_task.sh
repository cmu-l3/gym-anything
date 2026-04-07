#!/bin/bash
echo "=== Setting up steel_connection_detailing task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure output directory exists and is clean
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects
rm -f /home/ga/BIMProjects/steel_connection.ifc 2>/dev/null || true

# Kill any existing Blender instances
kill_blender

# Record task start timestamp (anti-gaming)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Launch empty Blender session for authoring
echo "Launching Blender (empty session)..."
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

# Extra wait to ensure UI is fully loaded
sleep 5

# Focus, maximize, and dismiss splash screens
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1

# Take initial screenshot for baseline
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender launched with empty session."
echo "Expected output: /home/ga/BIMProjects/steel_connection.ifc"