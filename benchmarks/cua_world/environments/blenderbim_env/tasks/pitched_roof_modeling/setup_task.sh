#!/bin/bash
echo "=== Setting up pitched_roof_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown -R ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to ensure a clean slate
rm -f /home/ga/BIMProjects/pitched_roof_house.ifc 2>/dev/null || true
rm -f /tmp/pitched_roof_result.json 2>/dev/null || true

# 3. Kill any existing Blender processes
kill_blender

# 4. Create project brief document on the Desktop for realistic context
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/rosewood_cottage_brief.txt << 'SPECEOF'
ARCHITECTURAL MODELLING BRIEF
=============================
Project:    Rosewood Cottage
Client:     Private Residential
Ref:        ARC-2024-RC-01
Date:       2024-03-15
Role:       Architectural BIM Technician

DELIVERABLE
-----------
Create a new IFC4 project from scratch in BlenderBIM/Bonsai.
Save the completed model to:
  /home/ga/BIMProjects/pitched_roof_house.ifc

IFC PROJECT SETUP
-----------------
  Project Name: Rosewood Cottage

MODELLING REQUIREMENTS
----------------------
1. Walls (IfcWall):
   - Model the ground floor perimeter using at least 4 wall elements.

2. Pitched Roof (IfcRoof / IfcSlab):
   - The building must have a pitched roof.
   - At least 1 IfcRoof element must exist (as a container or geometry).
   - The roof planes (slopes) must be modelled using at least 2 elements.
   - IMPORTANT: If using IfcSlab for the roof planes, you MUST change the
     IFC PredefinedType from FLOOR (default) to ROOF.

3. Roofing Material:
   - Create a new IFC material for the roof finish.
   - The material name must include one of the following words:
     Tile, Slate, Shingle, Clay, or Roof (e.g., "Clay Roof Tiles").
   - Assign this material to the roof elements using Bonsai's material
     assignment tool.

SPATIAL CONTAINMENT
-------------------
Standard IFC hierarchy applies (Project > Site > Building > Storey).
SPECEOF
chown ga:ga /home/ga/Desktop/rosewood_cottage_brief.txt
echo "Project brief placed on Desktop."

# 5. Record task start timestamp (Anti-gaming measure)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Launch Blender with a clean, empty session
echo "Launching Blender (empty session for new project authoring)..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window to appear
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

# 7. Focus, maximize, and dismiss dialogs
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender launched with empty session."
echo "Brief: /home/ga/Desktop/rosewood_cottage_brief.txt"
echo "Expected output: /home/ga/BIMProjects/pitched_roof_house.ifc"