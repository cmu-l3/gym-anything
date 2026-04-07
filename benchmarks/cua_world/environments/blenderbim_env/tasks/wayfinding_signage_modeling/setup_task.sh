#!/bin/bash
echo "=== Setting up wayfinding_signage_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/BIMProjects /home/ga/Desktop

# 2. Remove any existing output file
rm -f /home/ga/BIMProjects/fzk_wayfinding.ifc 2>/dev/null || true

# 3. Kill any existing Blender
kill_blender

# 4. Create Wayfinding EIR specification
cat > /home/ga/Desktop/wayfinding_eir.txt << 'SPECEOF'
WAYFINDING & SIGNAGE - EMPLOYER's INFORMATION REQUIREMENTS (EIR)
================================================================
Project:    FZK-Haus Residential Building
Discipline: Environmental Graphic Design / Wayfinding
Date:       2024-03-15

SCOPE
-----
The FZK-Haus IFC model is open in BlenderBIM/Bonsai. The project
requires basic wayfinding signage to be added prior to the 
final life-safety audit. 

TASK REQUIREMENTS
-----------------
1. Element Creation
   Model at least four (4) sign geometries (e.g., thin wall-mounted 
   boxes or planes) near doors or circulation areas.
   Assign them the IFC class: `IfcSign`.

2. Type Definition
   Create and assign at least two (2) distinct `IfcSignType` 
   definitions (e.g., "Exit Sign", "Room Plate").

3. Custom Property Set (CRITICAL FOR COBie / FM)
   Standard IFC property sets do not cover physical sign text.
   You MUST create a custom Property Set named exactly:
     Pset_Signage
   
   Inside this Pset, create a single-value string property named:
     SignText
   
   Populate `SignText` with the words printed on the sign 
   (e.g., "EXIT", "LIVING ROOM", "WC"). Apply this Pset to your signs.

4. Spatial Containment
   Ensure the signs are contained within a building storey 
   (Ground Floor or First Floor).

5. Save Deliverable
   Save the IFC project to: /home/ga/BIMProjects/fzk_wayfinding.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/wayfinding_eir.txt
echo "Wayfinding specification placed on Desktop"

# 5. Record task start timestamp
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus
cat > /tmp/load_fzk_wayfinding.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for wayfinding task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for Wayfinding task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_wayfinding.py > /tmp/blender_task.log 2>&1 &"

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

# 8. Focus, maximize, dismiss dialogs, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus loaded in Bonsai"
echo "Spec: /home/ga/Desktop/wayfinding_eir.txt"