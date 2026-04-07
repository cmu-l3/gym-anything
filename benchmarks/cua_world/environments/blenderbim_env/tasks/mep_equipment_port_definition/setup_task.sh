#!/bin/bash
echo "=== Setting up mep_equipment_port_definition task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_mep_boiler.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the MEP project brief on the Desktop ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/mep_boiler_spec.txt << 'SPECEOF'
MEP EQUIPMENT DEFINITION BRIEF
==============================
Project:    FZK-Haus MEP Coordination
Task:       Boiler Component Authoring
Date:       2024-03-15

The FZK-Haus residential model is currently open in Bonsai.
Before the MEP engineers can route pipework, we need a
logical mechanical component instantiated in the model.

REQUIREMENTS:
1. Model a simple geometric representation for a Boiler in the
   utility area (or anywhere inside the house).
2. Classify the object as an 'IfcBoiler'.
3. Assign at least TWO (2) 'IfcDistributionPort' entities to the boiler
   (representing the Flow In and Flow Out pipe connections).
   - This can be done via Bonsai's MEP tools / Object Properties,
     or via a python script in the internal console.
4. The ports MUST be structurally linked to the Boiler
   (typically via IfcRelNests or IfcRelConnectsPortToElement).
5. Save the project as an IFC file to:
   /home/ga/BIMProjects/fzk_mep_boiler.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/mep_boiler_spec.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_mep.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for MEP task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_mep.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time for IFC to load
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should now be loaded in Bonsai"
echo "Spec document: /home/ga/Desktop/mep_boiler_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_mep_boiler.ifc"