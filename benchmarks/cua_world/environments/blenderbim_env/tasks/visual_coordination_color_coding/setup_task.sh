#!/bin/bash
echo "=== Setting up visual_coordination_color_coding task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_color_coded.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create VDC instruction brief on Desktop ────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/vdc_color_coding_brief.txt << 'SPECEOF'
VDC COORDINATION PREP INSTRUCTIONS
==================================
Project: FZK-Haus Multidisciplinary Coordination
Role: VDC Specialist

OBJECTIVE
---------
We need to visually isolate specific walls during the Navisworks/Solibri 
clash detection meeting. We will do this by injecting a distinct blue 
surface style into the IFC model before federation.

INSTRUCTIONS
------------
1. Create a new material named exactly:
   Audit_Blue

2. Add an IFC Surface Style to this material.
   Set its Diffuse Color to a bright, distinct blue 
   (e.g., RGB: 0.0, 0.0, 1.0 or similar where Blue dominates).

3. Assign the "Audit_Blue" material to at least 4 IfcWall 
   elements in the 3D viewport.

4. Save the IFC project to:
   /home/ga/BIMProjects/fzk_color_coded.ifc

NOTE: Standard Blender materials do not export to IFC surface 
styles automatically. You must explicitly add an "IFC Surface Style" 
via the Bonsai Material Properties panel.
SPECEOF
chown ga:ga /home/ga/Desktop/vdc_color_coding_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_coordination.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for color coding task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for VDC coordination task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_coordination.py > /tmp/blender_task.log 2>&1 &"

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
sleep 10

# ── 8. Focus, maximize, screenshot ────────────────────────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Instructions: /home/ga/Desktop/vdc_color_coding_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_color_coded.ifc"