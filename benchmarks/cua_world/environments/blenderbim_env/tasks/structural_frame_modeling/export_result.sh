#!/bin/bash
echo "=== Exporting structural_frame_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/structural_frame_result.json"

cat > /tmp/export_structural.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/structural_frame.ifc"

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
        "n_columns": 0,
        "n_beams": 0,
        "n_slabs": 0,
        "n_materials": 0,
        "concrete_material_present": False,
        "structural_elements_with_material": 0,
        "total_structural_elements": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        columns = list(ifc.by_type("IfcColumn"))
        beams = list(ifc.by_type("IfcBeam"))
        slabs = list(ifc.by_type("IfcSlab"))
        materials = list(ifc.by_type("IfcMaterial"))

        # Check for a concrete-named material
        concrete_material_present = any(
            ("concrete" in (m.Name or "").lower() or
             "reinforced" in (m.Name or "").lower())
            for m in materials
        )

        # Find elements that have material associations
        elements_with_material = set()
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            for obj in (rel.RelatedObjects or []):
                elements_with_material.add(obj.id())

        structural_elements = columns + beams + slabs
        n_structural_with_mat = sum(
            1 for e in structural_elements if e.id() in elements_with_material
        )

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_columns": len(columns),
            "n_beams": len(beams),
            "n_slabs": len(slabs),
            "n_materials": len(materials),
            "material_names": [m.Name for m in materials if m.Name],
            "concrete_material_present": concrete_material_present,
            "structural_elements_with_material": n_structural_with_mat,
            "total_structural_elements": len(structural_elements),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_columns": 0,
            "n_beams": 0,
            "n_slabs": 0,
            "n_materials": 0,
            "concrete_material_present": False,
            "structural_elements_with_material": 0,
            "total_structural_elements": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_structural.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_columns":0,"n_beams":0,"n_slabs":0,"concrete_material_present":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
