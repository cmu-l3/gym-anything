#!/bin/bash
echo "=== Exporting landscape_site_context_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/landscape_result.json"

cat > /tmp/export_landscape.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_landscape.ifc"

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
        "n_geo": 0,
        "n_plants": 0,
        "n_target_elements": 0,
        "n_contained_in_site": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        # Retrieve geographic and plant elements
        geo_elements = list(ifc.by_type("IfcGeographicElement"))
        plant_elements = list(ifc.by_type("IfcPlant"))
        
        target_elements = geo_elements + plant_elements
        target_ids = {e.id() for e in target_elements}
        
        # Check spatial containment
        contained_in_site = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            if rel.RelatingStructure and rel.RelatingStructure.is_a("IfcSite"):
                for obj in (rel.RelatedElements or []):
                    if obj.id() in target_ids:
                        contained_in_site.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_geo": len(geo_elements),
            "n_plants": len(plant_elements),
            "n_target_elements": len(target_elements),
            "n_contained_in_site": len(contained_in_site),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_geo": 0,
            "n_plants": 0,
            "n_target_elements": 0,
            "n_contained_in_site": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_landscape.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_geo":0,"n_plants":0,"n_target_elements":0,"n_contained_in_site":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"