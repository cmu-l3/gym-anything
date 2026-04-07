#!/bin/bash
echo "=== Setting up ifc_model_subsetting task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_structural_only.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender instances ────────────────────────────────
kill_blender

# ── 4. Create task brief on Desktop for realism ───────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/subsetting_request.txt << 'SPECEOF'
BIM SUBSETTING REQUEST
======================
From: Structural Engineering Team
To: BIM Coordinator
Project: FZK-Haus

REQUEST
-------
We need to run finite element analysis on the FZK-Haus structure, but the
architectural model contains filling elements (doors and windows) that are 
cluttering our structural software and causing meshing errors.

Please prepare a "Structural Only" IFC file for us:
1. Delete all IfcDoor elements.
2. Delete all IfcWindow elements.
3. Keep all IfcWall and IfcSlab elements.
4. IMPORTANT: Keep the IfcOpeningElement entities (the voids/holes in the 
   walls) so we know where the structural penetrations are.

Save the stripped-down model to:
/home/ga/BIMProjects/fzk_structural_only.ifc

Thank you!
SPECEOF
chown ga:ga /home/ga/Desktop/subsetting_request.txt

# ── 5. Record task start timestamp (anti-gaming) ──────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_subset.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for subsetting task.")
        
        # Switch outliner to display IFC structure for easier filtering
        for area in bpy.context.screen.areas:
            if area.type == 'OUTLINER':
                space = area.spaces.active
                # Try to switch to Bonsai's spatial hierarchy view if available
                try:
                    space.display_mode = 'BIM_SPATIAL'
                except:
                    pass
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_subset.py > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window
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

# Extra time for IFC to load completely
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should now be loaded in Bonsai."
echo "Expected output: /home/ga/BIMProjects/fzk_structural_only.ifc"