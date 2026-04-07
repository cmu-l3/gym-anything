#!/bin/bash
echo "=== Setting up construction_work_schedule task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_construction_schedule.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the contractor schedule brief document on Desktop ───────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/contractor_schedule_brief.txt << 'SPECEOF'
CONTRACTOR'S PRELIMINARY SCHEDULE
=================================
Project: FZK-Haus Residential Building
Prepared by: Planning Department
Date: 2024-03-15
Reference: SCH-2024-FZK-001

INSTRUCTIONS
------------
Using BlenderBIM/Bonsai's Construction Scheduling tools, create a
4D work schedule for the FZK-Haus model currently open in the app.

STEP 1: Create a Work Schedule
  - Schedule Name: FZK-Haus Construction Programme
  - Predefined Type: PLANNED

STEP 2: Add Construction Tasks and Assign Elements
  Create tasks for the major build phases below. For each task,
  assign a duration (Task Time) and link the corresponding physical
  elements in the model.

  PHASE 1: Foundations & Ground Slab
    Duration: 14 days
    Elements: Ground floor IfcSlab elements

  PHASE 2: Ground Floor Walls
    Duration: 21 days
    Elements: Ground floor IfcWall elements

  PHASE 3: First Floor Slab
    Duration: 10 days
    Elements: Upper floor IfcSlab elements

  PHASE 4: First Floor Walls
    Duration: 21 days
    Elements: Upper floor IfcWall elements

  PHASE 5: Door Installation
    Duration: 7 days
    Elements: All IfcDoor elements

  PHASE 6: Window Installation
    Duration: 10 days
    Elements: All IfcWindow elements

  (Note: If you cannot easily distinguish ground vs first floor
  walls/slabs, you may assign them collectively to a single wall
  or slab task, provided at least 5 total tasks are created).

STEP 3: Save the project
  Save the completed IFC file (with the embedded schedule) to:
  /home/ga/BIMProjects/fzk_construction_schedule.ifc

NOTE: Bonsai's scheduling tools are typically located in the
scene properties or through the dedicated 4D/5D workspaces.
You must use Bonsai's formal 'Assign Product' action to link
elements to tasks.
SPECEOF
chown ga:ga /home/ga/Desktop/contractor_schedule_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_schedule.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for scheduling task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_schedule.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec document: /home/ga/Desktop/contractor_schedule_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_construction_schedule.ifc"