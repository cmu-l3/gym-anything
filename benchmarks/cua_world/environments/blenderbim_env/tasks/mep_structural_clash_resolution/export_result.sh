#!/bin/bash
echo "=== Exporting mep_structural_clash_resolution result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before extracting data
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/clash_result.json"

# ── Python extraction script using ifcopenshell ───────────────────────────
cat > /tmp/export_clash_resolution.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/clash_model_resolved.ifc"

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
        "duct_found": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        import ifcopenshell.util.placement
        import ifcopenshell.util.element
        
        ifc = ifcopenshell.open(ifc_path)
        
        # Locate the duct element
        ducts = [d for d in ifc.by_type("IfcDuctSegment") if d.Name == "Duct-Main"]
        
        if not ducts:
            result = {
                "file_exists": True,
                "file_mtime": os.path.getmtime(ifc_path),
                "duct_found": False,
                "task_start": task_start
            }
        else:
            duct = ducts[0]
            
            # Extract absolute coordinates using placement utility
            matrix = ifcopenshell.util.placement.get_local_placement(duct.ObjectPlacement)
            x, y, z = matrix[0][3], matrix[1][3], matrix[2][3]
            
            # Extract Property Sets
            psets = ifcopenshell.util.element.get_psets(duct)
            pset_coordination = psets.get("Pset_Coordination", {})
            status_value = pset_coordination.get("Status", "")
            
            result = {
                "file_exists": True,
                "file_mtime": os.path.getmtime(ifc_path),
                "duct_found": True,
                "duct_x": float(x),
                "duct_y": float(y),
                "duct_z": float(z),
                "has_pset_coordination": "Pset_Coordination" in psets,
                "status_value": str(status_value),
                "task_start": task_start
            }
            
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "duct_found": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run via headless Blender
/opt/blender/blender --background --python /tmp/export_clash_resolution.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"duct_found":false,"task_start":0,"error":"Export failed"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"