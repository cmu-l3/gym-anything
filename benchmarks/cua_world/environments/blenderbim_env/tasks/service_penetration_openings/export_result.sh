#!/bin/bash
echo "=== Exporting service_penetration_openings result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/opening_result.json"

cat > /tmp/export_openings.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_mep_openings.ifc"
baseline_path = "/tmp/initial_opening_counts.json"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

baseline = {
    "initial_openings": 0,
    "initial_voids": 0,
    "initial_wall_hosted": 0,
    "initial_with_geom": 0
}
if os.path.exists(baseline_path):
    try:
        with open(baseline_path, "r") as f:
            baseline = json.load(f)
    except Exception:
        pass

if not os.path.exists(ifc_path):
    result = {
        "file_exists": False,
        "file_mtime": 0.0,
        "final_openings": 0,
        "final_voids": 0,
        "final_wall_hosted": 0,
        "final_with_geom": 0,
        "task_start": task_start,
        **baseline
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        openings = list(ifc.by_type("IfcOpeningElement"))
        voids = list(ifc.by_type("IfcRelVoidsElement"))
        
        wall_hosted = 0
        for v in voids:
            host = v.RelatingBuildingElement
            opening = v.RelatedOpeningElement
            if host and opening and host.is_a("IfcWall") and opening.is_a("IfcOpeningElement"):
                wall_hosted += 1
                
        with_geom = 0
        for o in openings:
            if o.Representation and getattr(o.Representation, 'Representations', None):
                if len(o.Representation.Representations) > 0:
                    with_geom += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "final_openings": len(openings),
            "final_voids": len(voids),
            "final_wall_hosted": wall_hosted,
            "final_with_geom": with_geom,
            "task_start": task_start,
            **baseline
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "final_openings": 0,
            "final_voids": 0,
            "final_wall_hosted": 0,
            "final_with_geom": 0,
            "task_start": task_start,
            "error": str(e),
            **baseline
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_openings.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"