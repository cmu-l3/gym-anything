#!/bin/bash
echo "=== Exporting steel_connection_detailing result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/steel_connection_result.json"

# Write the python script that will run inside Blender to parse the saved IFC
cat > /tmp/export_steel_connection.py << 'PYEOF'
import sys
import json
import os

# Ensure ifcopenshell can be imported inside Blender
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/steel_connection.ifc"

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
        "n_plates": 0,
        "n_fasteners": 0,
        "steel_material_present": False,
        "elements_with_steel_material": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        columns = list(ifc.by_type("IfcColumn"))
        beams = list(ifc.by_type("IfcBeam"))
        plates = list(ifc.by_type("IfcPlate"))
        fasteners = list(ifc.by_type("IfcFastener"))

        # Check for steel material
        materials = list(ifc.by_type("IfcMaterial"))
        steel_material_present = any(
            "steel" in (m.Name or "").lower() for m in materials
        )

        # Count how many connection elements have a steel material assigned
        steel_assigned_elements = set()
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            rel_mat = rel.RelatingMaterial
            # RelatingMaterial can be IfcMaterial, IfcMaterialLayerSetUsage, etc.
            # We do a broad check on Name attributes in the material structure
            mat_name = ""
            if rel_mat.is_a("IfcMaterial"):
                mat_name = rel_mat.Name or ""
            elif rel_mat.is_a("IfcMaterialList"):
                mat_name = " ".join([m.Name or "" for m in rel_mat.Materials])
            elif getattr(rel_mat, "ForLayerSet", None):
                # Handle IfcMaterialLayerSetUsage
                ls = rel_mat.ForLayerSet
                mat_name = " ".join([l.Material.Name or "" for l in ls.MaterialLayers if l.Material])

            if "steel" in mat_name.lower():
                for obj in (rel.RelatedObjects or []):
                    steel_assigned_elements.add(obj.id())

        target_elements = columns + beams + plates + fasteners
        elements_with_steel = sum(1 for e in target_elements if e.id() in steel_assigned_elements)

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_columns": len(columns),
            "n_beams": len(beams),
            "n_plates": len(plates),
            "n_fasteners": len(fasteners),
            "steel_material_present": steel_material_present,
            "elements_with_steel_material": elements_with_steel,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_columns": 0,
            "n_beams": 0,
            "n_plates": 0,
            "n_fasteners": 0,
            "steel_material_present": False,
            "elements_with_steel_material": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Execute script in background Blender process
/opt/blender/blender --background --python /tmp/export_steel_connection.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback if script produced no output
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_columns":0,"n_beams":0,"n_plates":0,"n_fasteners":0,"steel_material_present":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"