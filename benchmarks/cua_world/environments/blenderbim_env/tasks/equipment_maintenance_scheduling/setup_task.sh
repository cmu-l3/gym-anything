#!/bin/bash
echo "=== Setting up equipment_maintenance_scheduling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_fm_maintenance.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the maintenance specification document on Desktop ───────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/fm_maintenance_spec.txt << 'SPECEOF'
FM MAINTENANCE SCHEDULING SPECIFICATION
=========================================
Project: FZK-Haus Residential Building
Prepared by: Operations & Maintenance Team
Date: 2024-03-15
Reference: FM-PPM-2024-001

INSTRUCTIONS
------------
Using BlenderBIM/Bonsai, enrich the FZK-Haus model with MEP plant
equipment and link them to their planned preventative maintenance
(PPM) tasks.

STEP 1: Model Plant Equipment
  - Model a basic 3D mesh representation of a Boiler on the Ground Floor.
    Assign it the IFC class: IfcBoiler
  - Model a basic 3D mesh representation of a Water Pump on the Ground Floor.
    Assign it the IFC class: IfcPump
  (Note: Exact geometry dimensions are not important, basic cubes or cylinders are fine).

STEP 2: Create a Maintenance Schedule
  - Navigate to Bonsai's sequence/scheduling tools (Sequence & Schedule).
  - Create a new Work Schedule (IfcWorkSchedule).
  - Name it EXACTLY: Annual PPM Schedule

STEP 3: Create Maintenance Tasks
  Within the new schedule, create TWO tasks (IfcTask):
  - Task 1 Name: Boiler Annual Service
  - Task 2 Name: Pump Inspection

STEP 4: Assign Equipment to Tasks (Process-to-Product Linking)
  - Assign the IfcBoiler element to the "Boiler Annual Service" task.
  - Assign the IfcPump element to the "Pump Inspection" task.
  (This establishes the IfcRelAssignsToProcess relationship required by the CMMS).

STEP 5: Save the Project
  Save the complete IFC file to:
  /home/ga/BIMProjects/fzk_fm_maintenance.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/fm_maintenance_spec.txt
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
        print("FZK-Haus IFC loaded successfully for FM maintenance task")
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
echo "Spec document: /home/ga/Desktop/fm_maintenance_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_fm_maintenance.ifc"