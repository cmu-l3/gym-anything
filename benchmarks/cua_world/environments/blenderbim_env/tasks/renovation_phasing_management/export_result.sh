#!/bin/bash
echo "=== Exporting renovation_phasing_management result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/renovation_result.json"

cat > /tmp/export_renovation.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_renovation_phased.ifc"

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
        "total_walls": 0,
        "status_existing": 0,
        "status_demolish": 0,
        "status_new": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        walls = ifc.by_type("IfcWall")
        total_walls = len(walls)
        
        status_existing = 0
        status_demolish = 0
        status_new = 0
        
        for w in walls:
            if not hasattr(w, "IsDefinedBy"):
                continue
            for rel in w.IsDefinedBy:
                if rel.is_a("IfcRelDefinesByProperties"):
                    pset = rel.RelatingPropertyDefinition
                    if pset and pset.is_a("IfcPropertySet") and pset.Name == "Pset_WallCommon":
                        if hasattr(pset, "HasProperties") and pset.HasProperties:
                            for prop in pset.HasProperties:
                                if prop.Name == "Status" and hasattr(prop, "NominalValue") and prop.NominalValue:
                                    val = str(prop.NominalValue.wrappedValue).strip().lower()
                                    if val == "existing":
                                        status_existing += 1
                                    elif val == "demolish":
                                        status_demolish += 1
                                    elif val == "new":
                                        status_new += 1
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "total_walls": total_walls,
            "status_existing": status_existing,
            "status_demolish": status_demolish,
            "status_new": status_new,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "total_walls": 0,
            "status_existing": 0,
            "status_demolish": 0,
            "status_new": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_renovation.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"total_walls":0,"status_existing":0,"status_demolish":0,"status_new":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"