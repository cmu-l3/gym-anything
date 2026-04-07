#!/bin/bash
echo "=== Setting up lighting_fixture_layout task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_lighting.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create project brief specification document ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/lighting_design_brief.txt << 'SPECEOF'
LIGHTING FIXTURE LAYOUT BRIEF
=============================
Project:    FZK-Haus Residential Building
Discipline: MEP / Lighting Design
Ref:        LD-2024-FZK-01
Date:       2024-03-15

DELIVERABLE
-----------
The FZK-Haus architectural model is currently open in BlenderBIM/Bonsai.
Your task is to add the preliminary lighting layout to this model.
Save the completed model to:
  /home/ga/BIMProjects/fzk_lighting.ifc

REQUIREMENTS
------------
1. FIXTURE MODELING & CLASSIFICATION
   - Model a minimum of 5 light fixtures (e.g., simple cylinders or disks 
     representing ceiling downlights) on the ground floor or upper floor.
   - You MUST classify these objects with the correct IFC class:
     IfcLightFixture

2. SPATIAL CONTAINMENT
   - All light fixtures must be contained within their respective building
     storey (e.g., Erdgeschoss / Ground Floor). Use Bonsai's spatial 
     management tools to assign the elements to a storey.

3. PROPERTY ENRICHMENT
   - To support downstream electrical load calculations, you must add 
     electrical/lighting properties to the fixtures.
   - Create a property set and add at least ONE of the following 
     properties to every fixture:
       * Wattage
       * LuminousFlux
       * Voltage
       * LightColor
   - Values can be estimated (e.g., Wattage = 15W, LuminousFlux = 900lm).

NOTES:
  - Do not alter the existing architectural walls/slabs/doors/windows.
  - Save the IFC project using Bonsai's Save IFC tool, not Blender's native save.
SPECEOF
chown ga:ga /home/ga/Desktop/lighting_design_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_lighting.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for lighting task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for MEP/Lighting task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_lighting.py > /tmp/blender_task.log 2>&1 &"

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

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Brief: /home/ga/Desktop/lighting_design_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_lighting.ifc"