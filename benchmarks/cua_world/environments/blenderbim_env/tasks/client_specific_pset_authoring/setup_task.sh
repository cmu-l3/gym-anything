#!/bin/bash
echo "=== Setting up client_specific_pset_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file
rm -f /home/ga/BIMProjects/fzk_eir_compliant.ifc 2>/dev/null || true

# 3. Kill any existing Blender
kill_blender

# 4. Create the EIR specification document on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/EIR_asset_requirements.txt << 'SPECEOF'
EMPLOYER'S INFORMATION REQUIREMENTS (EIR)
=========================================
Project:    University Campus - FZK Building
Client:     University Estates Department
Ref:        EIR-ASSET-2024-002
Date:       2024-03-15

SCOPE
-----
The FZK-Haus IFC model is open in BlenderBIM/Bonsai.
All maintainable architectural assets must be enriched with a
bespoke property set to support the university's CAFM system.

TARGET ASSETS
-------------
- Doors (IfcDoor)
- Windows (IfcWindow)

REQUIRED PROPERTY SET
---------------------
Property Set Name: Pset_ClientAssetData

You must add the following three properties to this Pset.
CRITICAL: You must explicitly set the correct IFC Data Type for each
property in the Bonsai interface (do not leave them as the default text).

1. Property: AssetID
   Data Type: IfcIdentifier (or IfcLabel / IfcText)
   Value: e.g., "D-01" or "W-05"

2. Property: ConditionScore
   Data Type: IfcInteger
   Value: 1 (acceptable range is 1-5)

3. Property: IsMaintainable
   Data Type: IfcBoolean (or IfcLogical)
   Value: True

TASK INSTRUCTIONS
-----------------
1. Select a door or window in the model.
2. Add the custom property set "Pset_ClientAssetData" with the exactly typed properties.
3. Apply this configured property set to at least 8 doors/windows in the model.
4. Save the enriched project to: /home/ga/BIMProjects/fzk_eir_compliant.ifc

Note: The FZK-Haus model contains 5 doors and 11 windows.
SPECEOF
chown ga:ga /home/ga/Desktop/EIR_asset_requirements.txt
echo "Project documentation placed on Desktop"

# 5. Record task start timestamp
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus
cat > /tmp/load_fzk_pset.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for custom pset task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_pset.py > /tmp/blender_task.log 2>&1 &"

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
echo "FZK-Haus should be loaded in Bonsai"
echo "Spec: /home/ga/Desktop/EIR_asset_requirements.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_eir_compliant.ifc"