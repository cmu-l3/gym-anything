#!/bin/bash
echo "=== Setting up security_system_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists and remove any old artifacts
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects
rm -f /home/ga/BIMProjects/fzk_security.ifc 2>/dev/null || true
rm -f /tmp/security_result.json 2>/dev/null || true

# 2. Kill any existing Blender process
kill_blender

# 3. Record task start timestamp for anti-gaming (file mtime check)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 4. Create Python startup script to pre-load the architectural model (FZK-Haus)
cat > /tmp/load_fzk_security.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for ELV security task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for Security/ELV modeling task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

# Register timer to allow UI to initialize before loading
bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 5. Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_security.py > /tmp/blender_task.log 2>&1 &"

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

# Wait for IFC to fully load in the UI
sleep 10

# 6. Focus, maximize, screenshot starting state
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Expected output: /home/ga/BIMProjects/fzk_security.ifc"