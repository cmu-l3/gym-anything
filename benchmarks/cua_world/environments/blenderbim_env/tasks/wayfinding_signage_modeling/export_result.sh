#!/bin/bash
echo "=== Exporting wayfinding_signage_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/wayfinding_result.json"

cat > /tmp/export_wayfinding.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_wayfinding.ifc"

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
        "n_signs": 0,
        "n_sign_types": 0,
        "n_signs_with_pset": 0,
        "n_signs_contained": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        signs = list(ifc.by_type("IfcSign"))
        types = list(ifc.by_type("IfcSignType"))
        
        n_signs = len(signs)
        n_sign_types = len(types)

        # Check for Custom Property Set "Pset_Signage" containing "SignText"
        n_signs_with_pset = 0
        for sign in signs:
            has_pset = False
            for rel in getattr(sign, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pdef = rel.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet") and pdef.Name == "Pset_Signage":
                        for prop in getattr(pdef, "HasProperties", []):
                            if getattr(prop, "Name", "") == "SignText":
                                has_pset = True
                                break
            if has_pset:
                n_signs_with_pset += 1

        # Check for spatial containment
        n_signs_contained = 0
        for sign in signs:
            is_contained = False
            for rel in getattr(sign, "ContainedInStructure", []):
                if rel.is_a("IfcRelContainedInSpatialStructure"):
                    is_contained = True
                    break
            if is_contained:
                n_signs_contained += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_signs": n_signs,
            "n_sign_types": n_sign_types,
            "n_signs_with_pset": n_signs_with_pset,
            "n_signs_contained": n_signs_contained,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_signs": 0,
            "n_sign_types": 0,
            "n_signs_with_pset": 0,
            "n_signs_contained": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_wayfinding.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_signs":0,"n_sign_types":0,"n_signs_with_pset":0,"n_signs_contained":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"