#!/bin/bash
echo "=== Setting up prefabricated_assembly_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to prevent false positives
rm -f /home/ga/BIMProjects/prefab_bathroom_pod.ifc 2>/dev/null || true

# 3. Kill any existing Blender instances
kill_blender

# 4. Create project brief specification document
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/bathroom_pod_brief.txt << 'SPECEOF'
PREFABRICATED ASSEMBLY BRIEF
============================
Component:      Modular Bathroom Pod (Type A)
Discipline:     DfMA / Prefabrication
Prepared by:    Lead Detailer
Date:           2024-03-15

DELIVERABLE
-----------
Create a new IFC4 project in BlenderBIM/Bonsai representing a
single prefabricated bathroom pod unit.

Save the completed model to:
  /home/ga/BIMProjects/prefab_bathroom_pod.ifc

IFC PROJECT SETUP
-----------------
  Establish a standard spatial hierarchy:
  Project > Site > Building > Storey (e.g., Ground Floor)

ASSEMBLY REQUIREMENTS
---------------------
  Create an IFC Assembly to represent the entire pod unit.
  - Entity Type: IfcElementAssembly
  - Name: "Bathroom Pod"

SUB-COMPONENTS REQUIRED
-----------------------
  Model the individual parts of the pod. Geometry can be simple
  boundary boxes or planar meshes, but the IFC classes must be exact:
  
  1. Walls: Minimum 3 x IfcWall elements (representing pod walls)
  2. Base: Minimum 1 x IfcSlab element (representing the pod floor pan)
  3. Fixture: Minimum 1 x IfcSanitaryTerminal (representing the toilet/basin)

AGGREGATION (CRITICAL)
----------------------
  All sub-components (walls, slab, sanitary terminal) MUST be
  aggregated into the Bathroom Pod assembly. In IFC terms, the
  IfcElementAssembly must relate to the components via an
  IfcRelAggregates relationship.
  (In Bonsai, this is typically achieved by parenting the component
  objects to the Assembly object in the Outliner).

SPATIAL CONTAINMENT
-------------------
  The IfcElementAssembly itself must be spatially contained within
  the Building Storey. Do NOT assign the individual sub-components
  to the storey; only the parent Assembly should be linked to the
  spatial structure.
SPECEOF
chown ga:ga /home/ga/Desktop/bathroom_pod_brief.txt
echo "Project documentation placed on Desktop"

# 5. Record task start timestamp for anti-gaming validation
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Launch Blender (empty session)
echo "Launching Blender (empty session for new assembly authoring)..."
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

# 7. Focus, maximize, dismiss dialogs, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender launched with empty session"
echo "Brief: /home/ga/Desktop/bathroom_pod_brief.txt"
echo "Expected output: /home/ga/BIMProjects/prefab_bathroom_pod.ifc"