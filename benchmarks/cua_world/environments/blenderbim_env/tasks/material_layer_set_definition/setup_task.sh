#!/bin/bash
echo "=== Setting up material_layer_set_definition task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_envelope_spec.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create thermal specification document on Desktop ───────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/thermal_envelope_spec.txt << 'SPECEOF'
THERMAL ENVELOPE SPECIFICATION
==============================
Project:    FZK-Haus Residential Building
Prepared by: Building Physics Consulting Group
Date:       2024-03-15
Purpose:    IFC Material Enrichment for Energy Simulation (EnEV / GEG)

INSTRUCTIONS
------------
The FZK-Haus architectural model is open in BlenderBIM/Bonsai.
The model geometry is complete, but the opaque envelope elements
lack composite material layer definitions needed for energy analysis.

Using Bonsai's IFC material tools, define the following
material layer sets and assign them to the model elements.

1. EXTERNAL WALL BUILD-UP
-------------------------
Create a material layer set for external walls and assign it to
the external wall elements in the model.

Layers (from outside to inside):
  Layer 1 - Material: Cement Render        | Thickness: 15 mm
  Layer 2 - Material: Concrete Block       | Thickness: 200 mm
  Layer 3 - Material: Mineral Wool         | Thickness: 100 mm
  Layer 4 - Material: Gypsum Plasterboard  | Thickness: 12.5 mm

2. FLOOR SLAB BUILD-UP
----------------------
Create a material layer set for the ground floor slab and assign it
to the slab elements in the model.

Layers (from top to bottom):
  Layer 1 - Material: Floor Tiles          | Thickness: 10 mm
  Layer 2 - Material: Cement Screed        | Thickness: 65 mm
  Layer 3 - Material: EPS Insulation       | Thickness: 50 mm
  Layer 4 - Material: Reinforced Concrete  | Thickness: 200 mm

OUTPUT DELIVERABLE
------------------
Save the enriched IFC project to:
/home/ga/BIMProjects/fzk_envelope_spec.ifc

NOTE: You may assign these layer sets to all walls and slabs
in the model to ensure full coverage. The thickness values can
be entered in mm or m depending on the project unit settings,
as long as they are numerically equivalent.
SPECEOF
chown ga:ga /home/ga/Desktop/thermal_envelope_spec.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_materials.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for material layer task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_materials.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time for IFC to finish loading geometry
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
echo "Spec document: /home/ga/Desktop/thermal_envelope_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_envelope_spec.ifc"