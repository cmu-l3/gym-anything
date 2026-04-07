#!/bin/bash
echo "=== Setting up building_condition_assessment task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to prevent gaming
rm -f /home/ga/BIMProjects/fzk_condition_assessment.ifc 2>/dev/null || true

# 3. Kill any existing Blender instances
kill_blender

# 4. Create condition assessment surveyor instructions
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/surveyor_instructions.txt << 'SPECEOF'
DILAPIDATION SURVEY & CONDITION ASSESSMENT INSTRUCTIONS
=======================================================
Project:    FZK-Haus Residential Building
Surveyor:   Building Condition Team
Date:       2024-05-20

CONTEXT:
A recent site survey revealed significant defects in several structural 
elements of the FZK-Haus. You must record these findings directly into 
the digital twin (the IFC model) currently open in Bonsai/BlenderBIM.

REQUIRED ACTIONS:

STEP 1: Identify Defective Elements
  Select at least 3 walls (IfcWall) and 1 slab (IfcSlab) anywhere in 
  the model to represent the defective elements.

STEP 2: Create a Remediation Group
  Using Bonsai's grouping tools, create a new IfcGroup.
  Name it EXACTLY: Defect Remediation
  Assign your selected defective elements to this group.

STEP 3: Assign Condition Properties
  For EACH of the defective elements in your group, add a custom 
  property set to document its state:
  
  - Property Set Name: Pset_Condition
  - Add Property 1: 
      Name: AssessmentCondition
      Value: Poor
  - Add Property 2:
      Name: AssessmentDescription
      Value: "Spalling concrete and severe water damage" (or similar brief text)

STEP 4: Save the Model
  Save the completed IFC file to:
  /home/ga/BIMProjects/fzk_condition_assessment.ifc

NOTE: Use Bonsai's "Save IFC Project" function, not Blender's native save.
SPECEOF
chown ga:ga /home/ga/Desktop/surveyor_instructions.txt
echo "Surveyor instructions placed on Desktop"

# 5. Record task start timestamp for anti-gaming verification
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus
cat > /tmp/load_fzk_assessment.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for condition assessment task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for condition assessment task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_assessment.py > /tmp/blender_task.log 2>&1 &"

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

# Allow time for Bonsai to parse and load the IFC geometry
sleep 10

# 8. Focus, maximize, dismiss dialogs, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Instructions: /home/ga/Desktop/surveyor_instructions.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_condition_assessment.ifc"