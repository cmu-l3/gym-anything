#!/bin/bash
echo "=== Setting up safety_hazard_zone_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file
rm -f /home/ga/BIMProjects/fzk_safety_hazards.ifc 2>/dev/null || true

# 3. Kill any existing Blender
kill_blender

# 4. Create the Safety Hazard Brief on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/safety_hazard_brief.txt << 'SPECEOF'
HEALTH & SAFETY (CDM) BIM REQUIREMENTS
======================================
Project:    FZK-Haus Residential Building
Phase:      Pre-Construction Coordination
Ref:        H&S-2024-FZK-001
Date:       2024-03-15

SCOPE
-----
Under CDM regulations, site hazards must be visually communicated to
the contractor in the federated BIM model. The architectural model
is open in BlenderBIM/Bonsai. You must model 3D warning volumes for
at least two distinct hazards (e.g., roof edge fall hazard, confined space).

TASK REQUIREMENTS
-----------------
STEP 1: Model Hazard Volumes
  - Create at least two 3D meshes (e.g., boxes) representing hazard zones.
  - Assign them the IFC class: IfcSpatialZone (or IfcBuildingElementProxy).
  - IMPORTANT: The 'Name' or 'Description' of these elements MUST
    contain the word "Hazard" or "Risk" (e.g., "Hazard: Roof Edge Fall").

STEP 2: Create Custom Metadata (Property Set)
  - Create a custom Property Set named exactly: Pset_Risk
  - Add two string properties to this Pset:
      1. RiskType   (e.g., "Fall from height")
      2. Mitigation (e.g., "Install temporary edge protection")
  - Assign this custom Pset to your modeled hazard volumes.

STEP 3: Material Assignment
  - Create a material (e.g., "Warning_Red") and assign it to your
    hazard volumes to make them visually distinct.

STEP 4: Export Deliverable
  - Save the completed IFC file to:
    /home/ga/BIMProjects/fzk_safety_hazards.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/safety_hazard_brief.txt
echo "Project documentation placed on Desktop"

# 5. Record task start timestamp
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus
cat > /tmp/load_fzk_safety.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for H&S task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for Safety Hazard Modeling task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_safety.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec: /home/ga/Desktop/safety_hazard_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_safety_hazards.ifc"