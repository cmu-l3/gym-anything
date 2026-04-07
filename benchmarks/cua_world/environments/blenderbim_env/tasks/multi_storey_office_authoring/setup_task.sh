#!/bin/bash
echo "=== Setting up multi_storey_office_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/meridian_office.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create project brief specification document ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/office_project_brief.txt << 'SPECEOF'
BIM PROJECT BRIEF
=================
Project Title:  Meridian Office Tower
Client:         Meridian Developments Ltd
Location:       City Centre, UK
Contract Ref:   MDL-2024-001
Brief Date:     2024-03-15
Prepared by:    BIM Technician (you)

DELIVERABLE
-----------
Create a new IFC4 project in BlenderBIM/Bonsai and model the
building structure as described below. Save the completed model to:
  /home/ga/BIMProjects/meridian_office.ifc

PROJECT DETAILS
---------------
IFC Project Name:  Meridian Office Tower
Building Name:     Meridian Office Tower - Block A
Site Name:         City Centre Site

STOREY CONFIGURATION (3 storeys required):
  Storey 1: Ground Floor    - Elevation: 0 mm     (0.000 m)
  Storey 2: First Floor     - Elevation: 3500 mm  (3.500 m)
  Storey 3: Second Floor    - Elevation: 7000 mm  (7.000 m)

WALLS PER STOREY:
  Each storey must have at least 4 external perimeter walls
  (representing the four sides of a rectangular floor plate).
  Total minimum wall count across all storeys: 12 walls

SPATIAL HIERARCHY REQUIRED:
  IfcProject > IfcSite > IfcBuilding > IfcBuildingStorey
  All walls must be spatially contained within their storey.

NOTES:
  - Use IFC4 schema
  - Wall type: IfcWall (standard)
  - Storey elevations entered in project units (mm or m as set)
  - Ensure the project name is set exactly as shown above
SPECEOF
chown ga:ga /home/ga/Desktop/office_project_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Launch Blender (empty, no file) ────────────────────────────────────
echo "Launching Blender (empty session for new project authoring)..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

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
sleep 3

# ── 7. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender launched with empty session"
echo "Brief: /home/ga/Desktop/office_project_brief.txt"
echo "Expected output: /home/ga/BIMProjects/meridian_office.ifc"
