#!/bin/bash
echo "=== Exporting fire_compartment_zone_definition result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/fire_compartment_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_fire_compartments.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_fire_compartments.ifc"

# Read task start timestamp
task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

if not os.path.exists(ifc_path):
    result = {
        "file_exists": False,
        "file_mtime": 0.0,
        "zone_count": 0,
        "rel_assigns_count": 0,
        "assigned_space_count": 0,
        "fire_prop_found": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        zones = ifc.by_type("IfcZone")
        zone_count = len(zones)
        
        assigned_spaces = set()
        rel_count = 0
        
        # Check space assignments
        for rel in ifc.by_type("IfcRelAssignsToGroup"):
            if rel.RelatingGroup and rel.RelatingGroup.is_a("IfcZone"):
                spaces_in_rel = [o for o in (rel.RelatedObjects or []) if o.is_a("IfcSpace")]
                if spaces_in_rel:
                    rel_count += 1
                    for s in spaces_in_rel:
                        assigned_spaces.add(s.id())
        
        assigned_space_count = len(assigned_spaces)
        
        # Check for fire properties
        fire_prop_found = False
        for zone in zones:
            for rel_def in getattr(zone, "IsDefinedBy", []):
                if rel_def.is_a("IfcRelDefinesByProperties"):
                    pset = rel_def.RelatingPropertyDefinition
                    if pset and pset.is_a("IfcPropertySet"):
                        if "fire" in (pset.Name or "").lower():
                            fire_prop_found = True
                        for prop in getattr(pset, "HasProperties", []):
                            if "fire" in (prop.Name or "").lower():
                                fire_prop_found = True
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "zone_count": zone_count,
            "rel_assigns_count": rel_count,
            "assigned_space_count": assigned_space_count,
            "fire_prop_found": fire_prop_found,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "zone_count": 0,
            "rel_assigns_count": 0,
            "assigned_space_count": 0,
            "fire_prop_found": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_fire_compartments.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"zone_count":0,"rel_assigns_count":0,"assigned_space_count":0,"fire_prop_found":false,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"