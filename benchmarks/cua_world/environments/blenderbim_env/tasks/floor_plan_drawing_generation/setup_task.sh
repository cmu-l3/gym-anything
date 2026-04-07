#!/bin/bash
echo "=== Setting up floor_plan_drawing_generation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure output directory exists and is strictly clean
mkdir -p /home/ga/BIMProjects
rm -rf /home/ga/BIMProjects/* 2>/dev/null || true
chown ga:ga /home/ga/BIMProjects

# Kill any existing Blender instances to ensure clean state
kill_blender

# Record task start timestamp for anti-gaming checks
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# Create Python startup script to pre-load FZK-Haus
cat > /tmp/load_fzk_drawing.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for drawing task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_drawing.py > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window mapping
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

# Extra time buffer for IFC data payload to finish loading
sleep 10

# Focus, maximize, dismiss splash screens, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus loaded in Bonsai"
echo "Expected outputs: "
echo "  1) /home/ga/BIMProjects/fzk_with_drawings.ifc"
echo "  2) Published SVG drawing file"