#!/bin/bash
echo "=== Setting up curtain_wall_facade_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/facade_curtainwall.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create facade brief specification document ─────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/facade_brief.txt << 'SPECEOF'
FACADE MODELING BRIEF
=====================
Project:    Greenfield Innovation Hub
Client:     Greenfield Corp
Ref:        GF-FACADE-2024-01
Date:       2024-03-15
Discipline: Envelope / Facade

DELIVERABLE
-----------
Create a new IFC4 project in BlenderBIM/Bonsai and model the
entrance curtain wall system as described below. Save the completed 
model to:
  /home/ga/BIMProjects/facade_curtainwall.ifc

PROJECT DETAILS
---------------
IFC Project Name:  Greenfield Innovation Hub

CURTAIN WALL SYSTEM REQUIRED
-----------------------------
Model a non-load-bearing entrance facade.

CONTAINER (IfcCurtainWall): Minimum 1 required
  - Create a parent or envelope entity correctly typed as IfcCurtainWall.

FRAMING (IfcMember): Minimum 3 required
  - Model mullions (vertical) and transoms (horizontal).
  - Assign IFC type: IfcMember

GLAZING (IfcPlate): Minimum 2 required
  - Model the glass infill panels between the framing.
  - Assign IFC type: IfcPlate

MATERIAL ASSIGNMENT
-------------------
Define a material for the glazing panels.
The material name MUST contain "Glass" or "Glazing" (e.g., "Clear Glass").
Associate this material with your glazing panels using standard IFC 
material assignment.

NOTES:
  - Do not use IfcWall or IfcBuildingElementProxy.
  - Geometry does not need to be highly detailed; correct IFC 
    classification and hierarchy are the primary requirements.
SPECEOF
chown ga:ga /home/ga/Desktop/facade_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Launch Blender (empty session) ─────────────────────────────────────
echo "Launching Blender (empty session for new facade modeling)..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

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
sleep 3

# ── 7. Focus, maximize, screenshot ────────────────────────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender launched with empty session"
echo "Brief: /home/ga/Desktop/facade_brief.txt"
echo "Expected output: /home/ga/BIMProjects/facade_curtainwall.ifc"