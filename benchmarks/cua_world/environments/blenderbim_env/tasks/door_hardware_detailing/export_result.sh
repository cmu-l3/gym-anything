#!/bin/bash
echo "=== Exporting door_hardware_detailing result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/door_hardware_result.json"

# Write the Python export script that extracts properties via ifcopenshell
cat > /tmp/export_hardware.py << 'PYEOF'
import sys
import json
import os
import math

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_doors_detailed.ifc"

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
        "n_accessories": 0,
        "n_nested_accessories": 0,
        "accessory_materials": [],
        "proximity_checks": [],
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        import ifcopenshell.util.placement
        
        ifc = ifcopenshell.open(ifc_path)
        
        def get_coords(element):
            try:
                matrix = ifcopenshell.util.placement.get_local_placement(element.ObjectPlacement)
                return (matrix[0][3], matrix[1][3], matrix[2][3])
            except:
                return None

        def calc_dist(c1, c2):
            if not c1 or not c2: return 9999.0
            return math.sqrt((c1[0]-c2[0])**2 + (c1[1]-c2[1])**2 + (c1[2]-c2[2])**2)

        accessories = list(ifc.by_type("IfcDiscreteAccessory"))
        
        # Find which accessories are nested into doors
        nested_acc_ids = set()
        proximity_checks = []
        
        for rel in ifc.by_type("IfcRelNests"):
            relating = rel.RelatingObject
            if relating and relating.is_a("IfcDoor"):
                door_coords = get_coords(relating)
                for related in (rel.RelatedObjects or []):
                    if related.is_a("IfcDiscreteAccessory"):
                        nested_acc_ids.add(related.id())
                        acc_coords = get_coords(related)
                        dist = calc_dist(door_coords, acc_coords)
                        proximity_checks.append(dist)

        # Find materials assigned to accessories
        acc_materials = set()
        for rel in ifc.by_type("IfcRelAssociatesMaterial"):
            mat = rel.RelatingMaterial
            mat_name = ""
            if mat and mat.is_a("IfcMaterial"):
                mat_name = mat.Name
            
            for related in (rel.RelatedObjects or []):
                if related.is_a("IfcDiscreteAccessory") and mat_name:
                    acc_materials.add(mat_name)

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_accessories": len(accessories),
            "n_nested_accessories": len(nested_acc_ids),
            "accessory_materials": list(acc_materials),
            "proximity_checks": proximity_checks,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_accessories": 0,
            "n_nested_accessories": 0,
            "accessory_materials": [],
            "proximity_checks": [],
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run via blender --background to access bundled ifcopenshell
/opt/blender/blender --background --python /tmp/export_hardware.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"