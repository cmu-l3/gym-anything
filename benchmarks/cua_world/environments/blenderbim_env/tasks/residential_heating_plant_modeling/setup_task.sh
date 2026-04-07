#!/bin/bash
echo "=== Setting up residential_heating_plant_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_heating_plant.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create MEP Plant Specification Document ────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/mep_plant_spec.txt << 'SPECEOF'
MEP PLANT SPECIFICATION
=======================
Project:    FZK-Haus Residential Building
System:     Primary Heating Plant
Date:       2024-03-15

SCOPE
-----
Model the primary mechanical equipment for the residential heating system.
The elements should be instantiated into the FZK-Haus model.

REQUIRED EQUIPMENT:
  1. Water Boiler
     - IFC Class: IfcBoiler
     - PredefinedType: WATER

  2. Hot Water Storage Cylinder
     - IFC Class: IfcTank
     - PredefinedType: STORAGE

  3. Circulation Pump
     - IFC Class: IfcPump

SYSTEM GROUPING:
  - Create an MEP system (IfcSystem) named "Heating Plant".
  - Add the boiler, tank, and pump to this system using 
    Bonsai's group/system assignment tools.

DELIVERABLE:
  - Save the updated IFC project to: 
    /home/ga/BIMProjects/fzk_heating_plant.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/mep_plant_spec.txt
echo "MEP Plant specification placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_mep.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for MEP modeling task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for MEP modeling task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_mep.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec: /home/ga/Desktop/mep_plant_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_heating_plant.ifc"