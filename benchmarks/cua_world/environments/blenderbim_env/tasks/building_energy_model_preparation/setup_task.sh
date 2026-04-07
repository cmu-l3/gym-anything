#!/bin/bash
echo "=== Setting up building_energy_model_preparation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/BIMProjects /home/ga/Desktop

# 2. Remove any existing output file to ensure a clean slate
rm -f /home/ga/BIMProjects/fzk_energy_model.ifc 2>/dev/null || true

# 3. Kill any existing Blender processes
kill_blender

# 4. Create a specification document for context (optional but helpful)
cat > /home/ga/Desktop/BEM_Preparation_Brief.txt << 'SPECEOF'
BEM PREPARATION BRIEF
=====================
Project: FZK-Haus Residential
Role: BEM Analyst

The architectural model requires preparation before exporting to EnergyPlus.

REQUIRED TASKS:
1. Spatial Topology:
   - The architectural spaces lack thermal boundary definitions.
   - Use Bonsai's spatial tools to generate Space Boundaries (IfcRelSpaceBoundary).
   - Generate boundaries for all spaces.

2. Thermal Design Conditions:
   - Assign the IFC standard property set 'Pset_SpaceThermalDesign' to at least 3 major spaces (IfcSpace).
   - Within this property set, define the design temperature by adding the property 'HeatingDryBulb' (e.g., 21.0) or 'CoolingDryBulb' (e.g., 24.0).

3. Deliverable:
   - Save the enriched model to: /home/ga/BIMProjects/fzk_energy_model.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/BEM_Preparation_Brief.txt

# 5. Record task start timestamp for anti-gaming verification
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load the FZK-Haus model
cat > /tmp/load_fzk_bem.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for BEM preparation task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for BEM preparation task")
        
        # Ensure we are in the Bonsai workspace if possible
        for area in bpy.context.screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces[0].shading.type = 'SOLID'
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

# Register timer to run load after UI initializes
bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with the FZK-Haus model pre-loaded
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_bem.py > /tmp/blender_task.log 2>&1 &"

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

# Give the script time to execute the IFC load
sleep 10

# 8. Focus, maximize, and screenshot initial state
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Expected output: /home/ga/BIMProjects/fzk_energy_model.ifc"