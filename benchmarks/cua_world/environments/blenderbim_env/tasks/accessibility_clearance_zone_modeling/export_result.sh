#!/bin/bash
echo "=== Exporting accessibility_clearance_zone_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/accessibility_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_accessibility.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_accessibility.ifc"

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
        "n_walls": 0,
        "n_virtual_elements": 0,
        "virtual_elements_data": [],
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        walls = ifc.by_type("IfcWall")
        
        # Build set of all elements contained in a spatial structure
        contained_ids = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            for elem in (rel.RelatedElements or []):
                contained_ids.add(elem.id())
                
        # Inspect Virtual Elements
        virtual_elems = ifc.by_type("IfcVirtualElement")
        v_data = []
        for v in virtual_elems:
            v_data.append({
                "id": v.id(),
                "name": v.Name or "",
                "contained": v.id() in contained_ids
            })

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": len(walls),
            "n_virtual_elements": len(virtual_elems),
            "virtual_elements_data": v_data,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": 0,
            "n_virtual_elements": 0,
            "virtual_elements_data": [],
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_accessibility.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_walls":0,"n_virtual_elements":0,"virtual_elements_data":[],"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"