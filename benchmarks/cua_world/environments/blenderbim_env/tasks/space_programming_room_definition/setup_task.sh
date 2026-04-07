#!/bin/bash
echo "=== Setting up space_programming_room_definition task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_spaces.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create space programming brief specification ───────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/space_programming_brief.txt << 'SPECEOF'
SPACE PROGRAMMING BRIEF
=======================
Project:    FZK-Haus Residential Building
Client:     FZK Estate Management
Ref:        FM-SPACE-2024-002
Date:       2024-03-15

DELIVERABLE
-----------
The FZK-Haus architectural model is open in BlenderBIM/Bonsai.
It currently lacks room/space definitions. You must enrich the
model by adding IfcSpace entities for the primary rooms.

Save the completed model to:
  /home/ga/BIMProjects/fzk_spaces.ifc

ROOM SCHEDULE
-------------
Create IfcSpace entities for the following rooms.
Each space MUST be spatially contained within its corresponding storey.

Ground Floor (Erdgeschoss) Spaces:
  1. Living Room
  2. Kitchen
  3. Hallway

Upper Floor (Obergeschoss) Spaces:
  4. Bedroom 1
  5. Bedroom 2
  6. Bathroom

PROPERTY REQUIREMENTS
---------------------
For every space you create, you must populate the following:

  1. LongName: The human-readable room name (e.g., "Living Room")
  2. PredefinedType: Must be explicitly set to "SPACE"
     (Bonsai may default to NOTDEFINED; you must change this)

NOTES:
  - Exact 3D boundaries/geometry for spaces are NOT required for
    this stage. Representing the spaces semantically and assigning
    them to the correct building storey is sufficient.
  - You can create additional rooms if desired; the schedule
    above represents the minimum requirement.
SPECEOF
chown ga:ga /home/ga/Desktop/space_programming_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_spaces.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for space programming task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for space programming task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_spaces.py > /tmp/blender_task.log 2>&1 &"

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
echo "Brief: /home/ga/Desktop/space_programming_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_spaces.ifc"