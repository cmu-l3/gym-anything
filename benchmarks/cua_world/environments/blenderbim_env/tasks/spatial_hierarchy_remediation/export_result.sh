#!/bin/bash
echo "=== Exporting spatial_hierarchy_remediation result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/remediation_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_remediation.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_repaired.ifc"

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
        "building_direct_elements": 0,
        "storeys": [],
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Check IfcBuilding for direct geometric elements
        building_direct_elements = 0
        buildings = ifc.by_type("IfcBuilding")
        if buildings:
            building = buildings[0]
            for rel in getattr(building, "ContainsElements", []):
                building_direct_elements += len(rel.RelatedElements)
                
        # 2. Extract storey information
        storeys_data = []
        for s in ifc.by_type("IfcBuildingStorey"):
            element_count = 0
            for rel in getattr(s, "ContainsElements", []):
                element_count += len(rel.RelatedElements)
                
            elev = 0.0
            try:
                if s.Elevation is not None:
                    elev = float(s.Elevation)
            except Exception:
                pass
                
            storeys_data.append({
                "name": s.Name or "",
                "elevation": elev,
                "element_count": element_count
            })
            
        # Sort storeys by elevation ascending
        storeys_data.sort(key=lambda x: x["elevation"])

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "building_direct_elements": building_direct_elements,
            "storeys": storeys_data,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "building_direct_elements": 0,
            "storeys": [],
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_remediation.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"building_direct_elements":0,"storeys":[],"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"