#!/bin/bash
echo "=== Exporting solar_shading_retrofit result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/solar_shading_result.json"

cat > /tmp/export_solar_shading.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_solar_shading.ifc"

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
        "n_shading_devices": 0,
        "n_valid_predefined_type": 0,
        "n_with_geometry": 0,
        "n_contained_in_storey": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        shading_devices = list(ifc.by_type("IfcShadingDevice"))
        n_shading_devices = len(shading_devices)
        
        n_valid_predefined_type = 0
        n_with_geometry = 0
        n_contained_in_storey = 0
        
        # Gather all elements that are spatially contained
        contained_elements = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            for obj in (getattr(rel, "RelatedElements", []) or []):
                contained_elements.add(obj.id())
                
        for sd in shading_devices:
            # Check PredefinedType
            ptype = getattr(sd, "PredefinedType", None)
            if ptype in ("AWNING", "LOUVER", "SHUTTER"):
                n_valid_predefined_type += 1
                
            # Check for 3D representation
            if getattr(sd, "Representation", None) is not None:
                n_with_geometry += 1
                
            # Check spatial containment
            if sd.id() in contained_elements:
                n_contained_in_storey += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_shading_devices": n_shading_devices,
            "n_valid_predefined_type": n_valid_predefined_type,
            "n_with_geometry": n_with_geometry,
            "n_contained_in_storey": n_contained_in_storey,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_shading_devices": 0,
            "n_valid_predefined_type": 0,
            "n_with_geometry": 0,
            "n_contained_in_storey": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_solar_shading.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"