#!/bin/bash
echo "=== Setting up rainwater_harvesting_system_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_rainwater_system.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the system brief specification document on Desktop ──────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/rainwater_system_spec.txt << 'SPECEOF'
MEP RETROFIT SPECIFICATION
==========================
Project: FZK-Haus Residential Building
Discipline: Public Health Engineering
System: Rainwater Harvesting Network
Date: 2024-03-15

INSTRUCTIONS
------------
The architectural FZK-Haus model is open in BlenderBIM/Bonsai.
Your task is to model a new non-potable rainwater harvesting system
and properly classify it using IFC4 standards.

STEP 1: Model the MEP Equipment
  Model 3D geometry for the following equipment (basic volumetric
  shapes like cylinders or boxes are perfectly acceptable):
  - 1x Rainwater Storage Tank -> Classify as IfcTank
  - 1x Distribution Pump      -> Classify as IfcPump

STEP 2: Model the Routing
  Model basic linear routing geometry connecting the system:
  - At least 2x Pipe Segments -> Classify as IfcPipeSegment

STEP 3: Define the IFC System
  MEP elements must be logically grouped by their service type.
  - Create a new System (IfcSystem)
  - Name it "Rainwater Harvesting System" (or any name containing
    "Rainwater", "Harvesting", "Reclaimed", or "Non-Potable")
  - Assign the Tank, Pump, and Pipe Segments to this new System.

STEP 4: Save the Project
  Save the ENTIRE IFC project (preserving all original architectural
  walls, doors, etc.) to:
  /home/ga/BIMProjects/fzk_rainwater_system.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/rainwater_system_spec.txt
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
        print("FZK-Haus IFC loaded successfully for MEP task")
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
echo "Spec document: /home/ga/Desktop/rainwater_system_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_rainwater_system.ifc"