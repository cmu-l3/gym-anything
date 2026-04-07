#!/bin/bash
echo "=== Setting up thermal_zone_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to ensure a clean slate
rm -f /home/ga/BIMProjects/fzk_thermal_zones.ifc 2>/dev/null || true

# 3. Kill any existing Blender processes
kill_blender

# 4. Create the Thermal Zoning Brief specification document on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/thermal_zoning_brief.txt << 'SPECEOF'
THERMAL ZONING BRIEF
====================
Project: FZK-Haus Residential Building
Prepared by: Sustainability & Building Physics Team
Date: 2024-03-15

INSTRUCTIONS
------------
The FZK-Haus model is open in BlenderBIM/Bonsai and contains 14 IfcSpace
entities representing individual rooms. Before we can export this to our
Building Energy Modeling (BEM) software, you must group these spaces into
thermal zones using IfcZone entities.

Using Bonsai's spatial and group management tools:

STEP 1: Create three distinct thermal zones (IfcZone) and name them exactly:
  1. "Living Zone"
  2. "Sleeping Zone"
  3. "Unconditioned Zone"

STEP 2: Assign IfcSpace entities to these zones:
  - Assign at least 4 spaces to the "Living Zone" (e.g., kitchen, living room, dining).
  - Assign at least 3 spaces to the "Sleeping Zone" (e.g., bedrooms).
  - Assign at least 2 spaces to the "Unconditioned Zone" (e.g., corridors, bathrooms).
  (Note: exact space selection is flexible as long as the minimum counts are met).

STEP 3: Assign Property Sets:
  - Add the standard property set "Pset_ZoneCommon" to at least ONE of
    your newly created thermal zones.

STEP 4: Save the project:
  - Save the completed IFC project using Bonsai to:
    /home/ga/BIMProjects/fzk_thermal_zones.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/thermal_zoning_brief.txt
echo "Thermal zoning brief placed on Desktop"

# 5. Record task start timestamp for anti-gaming (ensures file is saved after start)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus automatically
cat > /tmp/load_fzk_thermal.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the thermal zoning task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded successfully for thermal zoning task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with the startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_thermal.py > /tmp/blender_task.log 2>&1 &"

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

# Allow extra time for the IFC model to finish loading in Blender
sleep 10

# 8. Focus, maximize, and screenshot initial state
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should now be loaded in Bonsai"
echo "Brief document: /home/ga/Desktop/thermal_zoning_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_thermal_zones.ifc"