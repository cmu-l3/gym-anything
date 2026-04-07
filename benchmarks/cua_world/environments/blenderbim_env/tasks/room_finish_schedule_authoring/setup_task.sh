#!/bin/bash
echo "=== Setting up room_finish_schedule_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/BIMProjects /home/ga/Desktop

# 2. Remove any existing output file to prevent gaming
rm -f /home/ga/BIMProjects/fzk_room_finishes.ifc 2>/dev/null || true

# 3. Kill any existing Blender instances
kill_blender

# 4. Create a quick reference brief on the desktop
cat > /home/ga/Desktop/room_finishes_brief.txt << 'SPECEOF'
INTERIOR FINISH SCHEDULE BRIEF
==============================
Project: FZK-Haus
Role: BIM Coordinator

Instructions:
We need to embed the room finishes directly into the IfcSpace
objects using the standard Pset_SpaceCoveringRequirements.

Requirements (Select at least 4 rooms):
- FloorCovering: 2 rooms need "Timber", 2 rooms need "Tile"
- WallCovering: All 4 rooms need "Paint"
- CeilingCovering: All 4 rooms need "Plasterboard"

Target Output:
/home/ga/BIMProjects/fzk_room_finishes.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/room_finishes_brief.txt

# 5. Record task start timestamp for anti-gaming verification
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load the FZK-Haus model
cat > /tmp/load_fzk_spaces.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded successfully for space enrichment task.")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with the pre-load script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_spaces.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time to ensure IFC file is fully loaded
sleep 10

# 8. Focus, maximize, and dismiss any startup dialogs
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1

# Take an initial screenshot proving the state before the agent acts
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus is loaded."
echo "Expected output: /home/ga/BIMProjects/fzk_room_finishes.ifc"