#!/bin/bash
echo "=== Setting up ifc_quality_schema_remediation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_remediated.ifc 2>/dev/null || true
rm -f /tmp/fzk_contaminated.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender processes ────────────────────────────────
kill_blender

# ── 4. Create the contaminated IFC file using ifcopenshell ────────────────
cat > /tmp/create_contaminated_ifc.py << 'PYEOF'
import sys
import os
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')
import ifcopenshell
import ifcopenshell.api

src = "/home/ga/IFCModels/fzk_haus.ifc"
dst = "/home/ga/IFCModels/fzk_contaminated.ifc"

try:
    ifc = ifcopenshell.open(src)

    # Error 1: Remove geographic coordinates from IfcSite
    for site in ifc.by_type("IfcSite"):
        site.RefLatitude = None
        site.RefLongitude = None
        site.RefElevation = None
        print(f"Contamination: Removed coordinates from site: {site.Name}")

    # Error 2: Remove building address from IfcBuilding
    for bldg in ifc.by_type("IfcBuilding"):
        bldg.BuildingAddress = None
        print(f"Contamination: Removed address from building: {bldg.Name}")

    # Error 3: Rename all IfcSpace to generic "Room"
    spaces = list(ifc.by_type("IfcSpace"))
    original_space_names = {}
    for i, space in enumerate(spaces):
        original_space_names[space.GlobalId] = space.Name or ""
        space.Name = "Room"
        space.LongName = "Room"
    print(f"Contamination: Renamed {len(spaces)} IfcSpace to 'Room'")

    # Error 4: Rename all IfcWall to generic "Wall"
    walls = list(ifc.by_type("IfcWall")) + list(ifc.by_type("IfcWallStandardCase"))
    seen_wall_ids = set()
    unique_walls = []
    for w in walls:
        if w.id() not in seen_wall_ids:
            seen_wall_ids.add(w.id())
            unique_walls.append(w)
    original_wall_names = {}
    for w in unique_walls:
        original_wall_names[w.GlobalId] = w.Name or ""
        w.Name = "Wall"
    print(f"Contamination: Renamed {len(unique_walls)} IfcWall to 'Wall'")

    ifc.write(dst)
    print(f"Contaminated IFC saved to: {dst}")

    # Write the original names for use in the validation report
    import json
    meta = {
        "original_space_names": original_space_names,
        "original_wall_names": original_wall_names
    }
    with open("/tmp/fzk_original_names.json", "w") as f:
        json.dump(meta, f, indent=2)
    print("Original names saved to /tmp/fzk_original_names.json")

except Exception as e:
    print(f"ERROR creating contaminated IFC: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

echo "Creating contaminated IFC model..."
/opt/blender/blender --background --python /tmp/create_contaminated_ifc.py 2>&1 | tail -20

if [ ! -f "/home/ga/IFCModels/fzk_contaminated.ifc" ]; then
    echo "ERROR: Failed to create contaminated IFC" >&2
    exit 1
fi
echo "Contaminated IFC created successfully"

# ── 5. Build the validation report from original names ────────────────────
mkdir -p /home/ga/Desktop
cat > /tmp/build_report.py << 'PYEOF'
import sys, json, os

try:
    with open("/tmp/fzk_original_names.json") as f:
        meta = json.load(f)
    space_names = list(meta["original_space_names"].values())
    wall_names = list(meta["original_wall_names"].values())
except Exception as e:
    print(f"WARNING: Could not load original names: {e}")
    # Fallback defaults
    space_names = ["Living Room", "Kitchen", "Bedroom 1", "Bedroom 2", "Bathroom", "Hallway", "Storage"]
    wall_names = ["EW01", "EW02", "EW03", "EW04", "IW01", "IW02", "IW03", "IW04", "IW05", "IW06", "IW07", "IW08", "IW09"]

report_lines = [
    "IFC MODEL VALIDATION REPORT - CRITICAL ERRORS",
    "=" * 50,
    "Project:     FZK-Haus Residential Building",
    "Audit Date:  2024-03-15",
    "Auditor:     BIM Quality Control System v4.2",
    "Standard:    ISO 16739-1:2018 (IFC4)",
    "",
    "CRITICAL ERRORS FOUND: 4",
    "All errors must be corrected before model handover.",
    "",
    "═" * 50,
    "ERROR 1 - IfcSite: Missing Geographic Coordinates",
    "═" * 50,
    "Severity:   CRITICAL",
    "Element:    IfcSite (all instances)",
    "Issue:      RefLatitude, RefLongitude, RefElevation are NULL",
    "Regulation: ISO 16739 requires georeferencing for site compliance",
    "",
    "REQUIRED FIX: Set the following coordinates on IfcSite:",
    "  RefLatitude:   49° 0' 48\" N  (stored as [49, 0, 48, 0])",
    "  RefLongitude:   8° 24' 16\" E (stored as [8, 24, 16, 0])",
    "  RefElevation:  116.0 m",
    "(These are the coordinates for KIT Campus, Karlsruhe, Germany)",
    "",
    "═" * 50,
    "ERROR 2 - IfcBuilding: Missing Postal Address",
    "═" * 50,
    "Severity:   CRITICAL",
    "Element:    IfcBuilding (all instances)",
    "Issue:      BuildingAddress attribute is NULL",
    "",
    "REQUIRED FIX: Add IfcPostalAddress with:",
    "  AddressLines:   ['Adenauerring 20b']",
    "  Town:           'Karlsruhe'",
    "  Region:         'Baden-Württemberg'",
    "  PostalCode:     '76131'",
    "  Country:        'Germany'",
    "",
    "═" * 50,
    "ERROR 3 - IfcSpace: Generic Names (Schema Violation)",
    "═" * 50,
    "Severity:   CRITICAL",
    "Count:      %d IfcSpace elements affected" % len(space_names),
    "Issue:      ALL IfcSpace elements have Name='Room' (non-unique)",
    "Regulation: ISO 16739 requires unique, meaningful element names",
    "",
    "REQUIRED FIX: Restore the original unique space names:",
]
for i, name in enumerate(space_names):
    report_lines.append("  Space %d: '%s'" % (i + 1, name))

report_lines += [
    "",
    "═" * 50,
    "ERROR 4 - IfcWall: Generic Names (Schema Violation)",
    "═" * 50,
    "Severity:   CRITICAL",
    "Count:      %d IfcWall elements affected" % len(wall_names),
    "Issue:      ALL IfcWall elements have Name='Wall' (non-unique)",
    "",
    "REQUIRED FIX: Restore the original unique wall names:",
]
for i, name in enumerate(wall_names):
    report_lines.append("  Wall %d: '%s'" % (i + 1, name))

report_lines += [
    "",
    "═" * 50,
    "REMEDIATION OUTPUT",
    "═" * 50,
    "Save the corrected model to:",
    "  /home/ga/BIMProjects/fzk_remediated.ifc",
    "",
    "Re-run this validation tool after saving to confirm",
    "all errors are resolved before handover.",
    "═" * 50,
]

report = "\n".join(report_lines)
with open("/home/ga/Desktop/validation_report.txt", "w") as f:
    f.write(report)
print("Validation report written")
print("DONE")
PYEOF

/opt/blender/blender --background --python /tmp/build_report.py 2>&1 | tail -5

chown ga:ga /home/ga/Desktop/validation_report.txt 2>/dev/null || true
echo "Validation report placed on Desktop"

# ── 6. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp

# ── 7. Create Python startup script to load the contaminated IFC ───────────
cat > /tmp/load_fzk_contaminated.py << 'PYEOF'
import bpy
import sys

def load_contaminated():
    """Load the contaminated FZK-Haus IFC for quality remediation task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_contaminated.ifc")
        print("Contaminated FZK-Haus loaded for quality remediation task")
    except Exception as e:
        print(f"Error loading contaminated IFC: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_contaminated, first_interval=4.0)
PYEOF

# ── 8. Launch Blender with contaminated IFC ───────────────────────────────
echo "Launching Blender with contaminated FZK-Haus..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_contaminated.py > /tmp/blender_task.log 2>&1 &"

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

# ── 9. Focus, maximize, dismiss dialogs, take initial screenshot ──────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Contaminated FZK-Haus loaded - all 4 errors are active"
echo "Validation report: /home/ga/Desktop/validation_report.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_remediated.ifc"
