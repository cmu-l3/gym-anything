#!/bin/bash
echo "=== Exporting curtain_wall_facade_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/curtainwall_result.json"

cat > /tmp/export_curtainwall.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/facade_curtainwall.ifc"

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
        "project_name": "",
        "n_curtain_walls": 0,
        "n_members": 0,
        "n_plates": 0,
        "glass_material_defined": False,
        "glass_material_assigned": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Project name
        projects = ifc.by_type("IfcProject")
        project_name = projects[0].Name if projects and projects[0].Name else ""

        # 2. Entity counts
        curtain_walls = ifc.by_type("IfcCurtainWall")
        members = ifc.by_type("IfcMember")
        plates = ifc.by_type("IfcPlate")

        # 3. Material defined
        materials = ifc.by_type("IfcMaterial")
        material_names = [m.Name for m in materials if m.Name]
        glass_defined = any(
            "glass" in n.lower() or "glazing" in n.lower()
            for n in material_names
        )

        # 4. Material assigned
        mat_assocs = ifc.by_type("IfcRelAssociatesMaterial")
        glass_assigned = False
        for assoc in mat_assocs:
            mat = assoc.RelatingMaterial
            mat_name = ""
            if mat:
                if mat.is_a("IfcMaterial"):
                    mat_name = mat.Name or ""
                elif hasattr(mat, "Name") and mat.Name:
                    mat_name = mat.Name
                elif mat.is_a("IfcMaterialLayerSetUsage"):
                    mat_name = str(mat)
            
            if "glass" in mat_name.lower() or "glazing" in mat_name.lower():
                # Check if it's assigned to any element
                if assoc.RelatedObjects and len(assoc.RelatedObjects) > 0:
                    glass_assigned = True
                    break

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": project_name,
            "n_curtain_walls": len(curtain_walls),
            "n_members": len(members),
            "n_plates": len(plates),
            "glass_material_defined": glass_defined,
            "glass_material_assigned": glass_assigned,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": "",
            "n_curtain_walls": 0,
            "n_members": 0,
            "n_plates": 0,
            "glass_material_defined": False,
            "glass_material_assigned": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_curtainwall.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"