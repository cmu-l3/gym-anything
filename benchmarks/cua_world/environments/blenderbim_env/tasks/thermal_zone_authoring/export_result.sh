#!/bin/bash
echo "=== Exporting thermal_zone_authoring result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/thermal_zone_result.json"

# Write the Python script that will extract the zone info using ifcopenshell
cat > /tmp/export_thermal_zone.py << 'PYEOF'
import sys
import json
import os

# Ensure ifcopenshell from Bonsai is in path
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_thermal_zones.ifc"

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
        "n_zones": 0,
        "living_zone_spaces": 0,
        "sleeping_zone_spaces": 0,
        "uncond_zone_spaces": 0,
        "has_pset_zone_common": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        zones = ifc.by_type("IfcZone")
        n_zones = len(zones)
        
        living_spaces = 0
        sleeping_spaces = 0
        uncond_spaces = 0
        has_pset_zone_common = False
        
        for z in zones:
            name = (z.Name or "").lower()
            
            # Count assigned IfcSpace elements
            space_count = 0
            for rel in getattr(z, "IsGroupedBy", []):
                if rel.is_a("IfcRelAssignsToGroup"):
                    for obj in (rel.RelatedObjects or []):
                        if obj.is_a("IfcSpace"):
                            space_count += 1
                            
            # Assign max space count matching substring criteria (in case they made multiple)
            if "living" in name:
                living_spaces = max(living_spaces, space_count)
            elif "sleeping" in name:
                sleeping_spaces = max(sleeping_spaces, space_count)
            elif "unconditioned" in name:
                uncond_spaces = max(uncond_spaces, space_count)
                
            # Check for Pset_ZoneCommon assigned to this zone
            for rel in getattr(z, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pdef = rel.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet"):
                        if pdef.Name == "Pset_ZoneCommon":
                            has_pset_zone_common = True

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_zones": n_zones,
            "zone_names": [z.Name for z in zones if z.Name],
            "living_zone_spaces": living_spaces,
            "sleeping_zone_spaces": sleeping_spaces,
            "uncond_zone_spaces": uncond_spaces,
            "has_pset_zone_common": has_pset_zone_common,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_zones": 0,
            "living_zone_spaces": 0,
            "sleeping_zone_spaces": 0,
            "uncond_zone_spaces": 0,
            "has_pset_zone_common": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run via Blender --background to utilize bundled ifcopenshell
/opt/blender/blender --background --python /tmp/export_thermal_zone.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback if export failed or produced no output
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_zones":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"