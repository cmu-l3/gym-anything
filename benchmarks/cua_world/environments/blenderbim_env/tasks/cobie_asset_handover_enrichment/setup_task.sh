#!/bin/bash
echo "=== Setting up cobie_asset_handover_enrichment task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_cobie.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender processes ────────────────────────────────
kill_blender

# ── 4. Create COBie handover specification ───────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/cobie_spec.txt << 'SPECEOF'
COBie ASSET HANDOVER ENRICHMENT SPECIFICATION
==============================================
Project:     FZK-Haus Residential Building
Client:      KIT Facility Management Division
Reference:   COBIE-HANDOVER-FZK-2024-001
Prepared by: Digital Facilities Management Solutions GmbH
Standard:    COBie (Construction Operations Building Exchange)
             BS 1192-4:2014 / ISO 29481-1

PURPOSE
-------
Enrich the FZK-Haus BIM model with COBie-compliant asset data
for digital handover to the building's Facilities Management team.
The CAFM (Computer-Aided Facility Management) system will import
this data directly from the IFC file.

The model is pre-loaded in Bonsai (BlenderBIM).
It contains 11 IfcWindow and 5 IfcDoor elements.

SECTION 1 - WINDOW MANUFACTURER DATA
--------------------------------------
Add the following to ALL 11 IfcWindow elements.

  Property Set: Pset_ManufacturerTypeInformation
    Manufacturer:              "Schuco International KG"
    ModelLabel:                "FW 60+"
    ProductionYear:            "2019"
    GlobalTradeItemNumber:     "4012236013245"

  This data populates COBie Component sheet columns:
  TypeAssetTagNumber, Manufacturer, ModelNumber, InstallationDate.

SECTION 2 - DOOR MANUFACTURER DATA
------------------------------------
Add the following to ALL 5 IfcDoor elements.

  Property Set: Pset_ManufacturerTypeInformation
    Manufacturer:              "Hormann KG"
    ModelLabel:                "THP Universal"
    ProductionYear:            "2021"
    GlobalTradeItemNumber:     "4034598167823"

SECTION 3 - WINDOW THERMAL COMMON PROPERTIES
----------------------------------------------
Add the following to ALL 11 IfcWindow elements.

  Property Set: Pset_WindowCommon
    IsExternal:              True          (IfcBoolean)
    ThermalTransmittance:    1.1           (IfcThermalTransmittanceMeasure)
    GlazingAreaFraction:     0.7           (IfcNormalisedRatioMeasure)

  Note: ThermalTransmittance 1.1 W/m²K is the U-value of the
  existing double-glazed units per manufacturer data sheet.

SECTION 4 - GLAZING PACKAGE GROUP
-----------------------------------
Create an IfcGroup to represent the glazing procurement package.

  IFC Class:    IfcGroup
  Name:         "Glazing Package"
  Description:  "All glazed window units - Schuco FW 60+ procurement batch"

  Assignment: Use IfcRelAssignsToGroup to add ALL 11 IfcWindow
  instances to this group.

  Purpose: Enables FM system to bulk-schedule glazing inspection
  and replacement as a single procurement action.

COBie SHEET MAPPING
-------------------
  Pset_ManufacturerTypeInformation → COBie Component sheet
  Pset_WindowCommon                → COBie Type sheet
  IfcGroup "Glazing Package"       → COBie System sheet

OUTPUT
------
Save the enriched model to:
  /home/ga/BIMProjects/fzk_cobie.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/cobie_spec.txt
echo "COBie handover specification placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_cobie.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the COBie handover enrichment task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for COBie asset handover enrichment task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_cobie.py > /tmp/blender_task.log 2>&1 &"

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

# ── 8. Focus, maximize, dismiss dialogs, take initial screenshot ──────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus loaded in Bonsai for COBie enrichment"
echo "Spec document: /home/ga/Desktop/cobie_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_cobie.ifc"
