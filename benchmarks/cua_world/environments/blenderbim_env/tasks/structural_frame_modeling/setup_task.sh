#!/bin/bash
echo "=== Setting up structural_frame_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/structural_frame.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create structural brief specification ──────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/structural_brief.txt << 'SPECEOF'
STRUCTURAL FRAMING MODEL BRIEF
================================
Project:    Hartwell Community Centre
Client:     Hartwell Borough Council
Ref:        HBC-STRUCT-2024-003
Date:       2024-03-15
Discipline: Structural Engineering (BIM)

DELIVERABLE
-----------
Create a new IFC4 structural framing model in BlenderBIM/Bonsai.
Save the completed model to:
  /home/ga/BIMProjects/structural_frame.ifc

IFC PROJECT SETUP
-----------------
  Project Name: Hartwell Community Centre - Structural
  Site Name:    Hartwell Site
  Building:     Community Centre Block
  Storey:       Ground Floor (Elevation: 0 m)

STRUCTURAL ELEMENTS REQUIRED
-----------------------------

COLUMNS (IfcColumn): Minimum 4 required
  - Arrange in a 2x2 or larger regular grid pattern
  - Designation: RC Column 400x400 (reinforced concrete, 400mm x 400mm)
  - IFC type: IfcColumn

BEAMS (IfcBeam): Minimum 4 required
  - Connect columns along both grid directions
  - Designation: RC Beam 300x600 (reinforced concrete, 300mm wide x 600mm deep)
  - IFC type: IfcBeam

SLAB (IfcSlab): 1 required
  - Ground floor slab covering the structural bay
  - Designation: RC Slab 200mm (reinforced concrete, 200mm thick)
  - IFC type: IfcSlab

MATERIAL ASSIGNMENT
-------------------
ALL structural elements (columns, beams, slab) must be assigned
a material. Create a material named:
  "Reinforced Concrete C30/37"

This material must be associated with ALL structural elements
using IFC material associations.

SPATIAL CONTAINMENT
-------------------
All elements must be spatially contained within the Ground Floor storey.

NOTES:
  - Use IFC4 schema
  - Minimum element counts are mandatory; more elements are acceptable
  - Material name must contain "Concrete" or "Reinforced"
SPECEOF
chown ga:ga /home/ga/Desktop/structural_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Launch Blender (empty session) ─────────────────────────────────────
echo "Launching Blender (empty session for structural modeling)..."
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
echo "Brief: /home/ga/Desktop/structural_brief.txt"
echo "Expected output: /home/ga/BIMProjects/structural_frame.ifc"
