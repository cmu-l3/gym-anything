#!/bin/bash
echo "=== Setting up hvac_system_grouping_and_specification task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/hvac_system.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender processes ────────────────────────────────
kill_blender

# ── 4. Create the HVAC design brief ──────────────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/hvac_brief.txt << 'SPECEOF'
HVAC SUPPLY AIR DISTRIBUTION SYSTEM - BIM DESIGN BRIEF
========================================================
Project:     Meridian House Office Fit-Out
Client:      Meridian Properties Ltd
Reference:   MEP-BIM-HVAC-2024-011
Prepared by: Advanced Building Services Consultants LLP
Service:     Supply Air Distribution - Level 3

PURPOSE
-------
Create an IFC4 Building Services model for the supply air
distribution system serving the open plan office area.
This model will form part of the federated BIM deliverable
and must be authored in Bonsai (BlenderBIM).

START CONDITION
---------------
A new blank IFC4 project is already open in Bonsai.
Create all elements from scratch in this project.

SECTION 1 - AIR HANDLING UNIT
-------------------------------
Create one IfcUnitaryEquipment representing the central AHU.

  IFC Class:    IfcUnitaryEquipment
  Name:         AHU-01
  ObjectType:   AirHandlingUnit

  Property Set: Pset_UnitaryEquipmentAirHandlingUnit
    NominalSupplyAirFlowRate:  "2500 L/s"   (IfcText)
    NominalCoolingCapacity:    "45 kW"      (IfcText)
    NominalHeatingCapacity:    "50 kW"      (IfcText)

SECTION 2 - DUCT SEGMENTS
--------------------------
Create a minimum of 4 IfcDuctSegment elements representing
the main supply ductwork from the AHU to each zone.

  IFC Class:    IfcDuctSegment
  Naming:       DS-01, DS-02, DS-03, DS-04 (minimum)
  ObjectType:   RECTANGULAR

  Property Set on each: Pset_DuctSegmentTypeCommon
    CrossSectionArea:  "0.6 m²"   (IfcText)
    FlowVelocity:      "5 m/s"    (IfcText)

SECTION 3 - AIR TERMINALS
--------------------------
Create a minimum of 2 IfcAirTerminal elements (supply grilles).

  IFC Class:    IfcAirTerminal
  Names:        AT-01, AT-02 (minimum)
  ObjectType:   GRILLE

  Property Set on each: Pset_AirTerminalTypeCommon
    NominalAirFlowRate:  "150 L/s"  (IfcText)

SECTION 4 - SYSTEM GROUPING
-----------------------------
Group ALL mechanical elements (AHU + all ducts + all terminals)
into a single IFC system object.

  IFC Class:    IfcSystem
  Name:         "HVAC Supply Air System"
  ObjectType:   "HVAC"

  All elements must be assigned using IfcRelAssignsToGroup.

SPATIAL PLACEMENT
-----------------
Place all elements within a valid IFC spatial hierarchy:
  IfcProject > IfcSite > IfcBuilding > IfcBuildingStorey

The spatial hierarchy may use default names (e.g. "My Project",
"Default", "Ground Floor").

OUTPUT
------
Save the completed HVAC model to:
  /home/ga/BIMProjects/hvac_system.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/hvac_brief.txt
echo "HVAC design brief placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Launch Blender with a fresh IFC4 project ───────────────────────────
# We launch Blender with a Python script that creates a fresh IFC4 project
cat > /tmp/init_hvac_project.py << 'PYEOF'
import bpy
import sys

def create_new_ifc4_project():
    """Initialize a new IFC4 project for the HVAC modeling task."""
    try:
        # Create a new IFC project via Bonsai
        bpy.ops.bim.create_project()
        print("New IFC4 project created for HVAC system task")
    except Exception as e:
        print(f"Error creating IFC4 project: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(create_new_ifc4_project, first_interval=4.0)
PYEOF

echo "Launching Blender with blank IFC4 project..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/init_hvac_project.py > /tmp/blender_task.log 2>&1 &"

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

sleep 8

# ── 7. Focus, maximize, dismiss dialogs, take initial screenshot ──────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blank IFC4 project ready in Bonsai"
echo "Brief document: /home/ga/Desktop/hvac_brief.txt"
echo "Expected output: /home/ga/BIMProjects/hvac_system.ifc"
