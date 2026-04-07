#!/bin/bash
echo "=== Exporting temporary_scaffolding_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/scaffold_result.json"

cat > /tmp/export_scaffold.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_scaffold.ifc"

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
        "n_members": 0,
        "n_plates": 0,
        "n_assemblies": 0,
        "max_aggregated_components": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        members = list(ifc.by_type("IfcMember"))
        plates = list(ifc.by_type("IfcPlate"))
        assemblies = list(ifc.by_type("IfcElementAssembly"))
        
        max_aggregated = 0
        
        for rel in ifc.by_type("IfcRelAggregates"):
            if rel.RelatingObject and rel.RelatingObject.is_a("IfcElementAssembly"):
                related = rel.RelatedObjects or []
                count = sum(1 for obj in related if obj.is_a("IfcMember") or obj.is_a("IfcPlate"))
                if count > max_aggregated:
                    max_aggregated = count
                    
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_members": len(members),
            "n_plates": len(plates),
            "n_assemblies": len(assemblies),
            "max_aggregated_components": max_aggregated,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_members": 0,
            "n_plates": 0,
            "n_assemblies": 0,
            "max_aggregated_components": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_scaffold.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_members":0,"n_plates":0,"n_assemblies":0,"max_aggregated_components":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"