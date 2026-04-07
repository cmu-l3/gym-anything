#!/bin/bash
echo "=== Setting up acoustic_performance_pset_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_acoustic.ifc 2>/dev/null || true
rm -f /home/ga/IFCModels/fzk_acoustic_ready.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender processes ────────────────────────────────
kill_blender

# ── 4. Pre-process FZK-Haus: rename walls to EW/IW convention ────────────
cat > /tmp/prepare_acoustic_ifc.py << 'PYEOF'
import sys, json, os
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')
import ifcopenshell

src = "/home/ga/IFCModels/fzk_haus.ifc"
dst = "/home/ga/IFCModels/fzk_acoustic_ready.ifc"

try:
    ifc = ifcopenshell.open(src)

    # Classify walls: external vs internal based on IsExternal property
    # or position heuristics. We assign EW01..EWn and IW01..IWm names.
    walls = list(ifc.by_type("IfcWall")) + list(ifc.by_type("IfcWallStandardCase"))
    seen_ids = set()
    unique_walls = []
    for w in walls:
        if w.id() not in seen_ids:
            seen_ids.add(w.id())
            unique_walls.append(w)

    ew_count = 0
    iw_count = 0
    wall_names = {}
    for w in unique_walls:
        # Check IsExternal property in any pset
        is_external = False
        for inv in ifc.get_inverse(w):
            if inv.is_a("IfcRelDefinesByProperties"):
                pdef = inv.RelatingPropertyDefinition
                if pdef and pdef.is_a("IfcPropertySet"):
                    for p in (pdef.HasProperties or []):
                        if p.Name == "IsExternal":
                            try:
                                val = p.NominalValue.wrappedValue
                                if val is True or val == "TRUE" or str(val).upper() == "TRUE":
                                    is_external = True
                            except Exception:
                                pass

        if is_external:
            ew_count += 1
            new_name = "EW%02d" % ew_count
        else:
            iw_count += 1
            new_name = "IW%02d" % iw_count

        w.Name = new_name
        wall_names[w.GlobalId] = new_name

    print(f"Renamed {ew_count} external walls (EW) and {iw_count} internal walls (IW)")

    # Also rename IfcSpace to meaningful names for the zones
    spaces = list(ifc.by_type("IfcSpace"))
    space_names_map = {}
    default_names = ["Living Room", "Kitchen", "Bedroom 1", "Bedroom 2", "Bathroom", "Hallway", "Storage"]
    for i, s in enumerate(spaces):
        if i < len(default_names):
            if not s.Name or len(s.Name.strip()) < 3:
                s.Name = default_names[i]
            s.LongName = s.Name
        space_names_map[s.GlobalId] = s.Name

    ifc.write(dst)
    meta = {"wall_names": wall_names, "ew_count": ew_count, "iw_count": iw_count,
            "space_names": space_names_map}
    with open("/tmp/acoustic_model_meta.json", "w") as f:
        json.dump(meta, f, indent=2)
    print(f"Acoustic-ready IFC saved to {dst}")
    print(f"Model meta: {ew_count} EW walls, {iw_count} IW walls, {len(spaces)} spaces")
    print("DONE")
except Exception as e:
    print(f"ERROR preparing acoustic IFC: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

echo "Pre-processing FZK-Haus for acoustic task..."
/opt/blender/blender --background --python /tmp/prepare_acoustic_ifc.py 2>&1 | tail -10

if [ ! -f "/home/ga/IFCModels/fzk_acoustic_ready.ifc" ]; then
    echo "ERROR: Failed to prepare acoustic IFC" >&2
    exit 1
fi
echo "Acoustic-ready IFC created"

# ── 5. Create the acoustic specification document ─────────────────────────
mkdir -p /home/ga/Desktop

# Read wall counts from meta
EW_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/acoustic_model_meta.json')); print(d['ew_count'])" 2>/dev/null || echo "4")
IW_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/acoustic_model_meta.json')); print(d['iw_count'])" 2>/dev/null || echo "9")

cat > /home/ga/Desktop/acoustic_spec.txt << SPECEOF
ACOUSTIC PERFORMANCE DATA AUTHORING SPECIFICATION
==================================================
Project:     FZK-Haus Residential Building
Client:      Federal Institute of Technology (KIT)
Reference:   ACOUSTIC-COMPLY-2024-FZK
Prepared by: Arup Acoustics & Building Performance Group
Standard:    UK Building Regulations Part E (Resistance to Sound)
             ISO 140-3 / ISO 717-1

PURPOSE
-------
Enrich the FZK-Haus IFC model with acoustic performance data
required for Building Regulations Part E compliance submission.
The model is pre-loaded in Bonsai. The walls are pre-named
using the EW (external wall) and IW (internal wall) convention.

MODEL INVENTORY
---------------
  External walls (prefix EW):  ${EW_COUNT} elements
  Internal walls (prefix IW):  ${IW_COUNT} elements
  Total walls:                 $((EW_COUNT + IW_COUNT)) elements

SECTION 1 - EXTERNAL WALL ACOUSTIC RATING
------------------------------------------
Add the 'AcousticRating' property to Pset_WallCommon on
ALL external walls (IfcWall elements with Name starting 'EW').

  Property Set:  Pset_WallCommon
  Property:      AcousticRating
  Value:         "Rw 52 dB"       (IfcText)

  This is the weighted sound reduction index per ISO 717-1.
  Apply to ALL ${EW_COUNT} external wall elements.

SECTION 2 - INTERNAL WALL ACOUSTIC PROPERTY SET
-------------------------------------------------
Create a custom property set on ALL internal walls
(IfcWall elements with Name starting 'IW').

  Property Set Name: Pset_AcousticPerformance

  Properties:
    SoundTransmissionClass:  45          (IfcInteger)
    ImpactInsulationClass:   50          (IfcInteger)
    FlankingTransmission:    "Controlled" (IfcText)

  The STC of 45 meets the minimum separating wall requirement.
  Apply to ALL ${IW_COUNT} internal wall elements.

SECTION 3 - ACOUSTIC ZONE CREATION
------------------------------------
Create two IfcZone instances grouping the existing IfcSpace
elements. IfcZone is used here to define acoustic control areas.

  Zone A:  "Acoustic Zone A - Living"
           Contains: Living Room, Kitchen
           Rationale: Open-plan daytime use areas

  Zone B:  "Acoustic Zone B - Sleeping"
           Contains: Bedroom 1, Bedroom 2
           Rationale: Quiet sleeping areas (sensitive receptors)

  Use IfcRelAssignsToGroup to assign spaces to each zone.

OUTPUT
------
Save the enriched model to:
  /home/ga/BIMProjects/fzk_acoustic.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/acoustic_spec.txt
echo "Acoustic specification placed on Desktop"

# ── 6. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp

# ── 7. Launch Blender with acoustic-ready IFC ─────────────────────────────
cat > /tmp/load_fzk_acoustic.py << 'PYEOF'
import bpy
import sys

def load_acoustic_model():
    """Load acoustic-ready FZK-Haus IFC for acoustic pset authoring task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_acoustic_ready.ifc")
        print("Acoustic-ready FZK-Haus loaded for pset authoring task")
    except Exception as e:
        print(f"Error loading IFC: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_acoustic_model, first_interval=4.0)
PYEOF

echo "Launching Blender with acoustic-ready FZK-Haus..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_acoustic.py > /tmp/blender_task.log 2>&1 &"

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
echo "Acoustic-ready FZK-Haus loaded in Bonsai"
echo "Spec document: /home/ga/Desktop/acoustic_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_acoustic.ifc"
