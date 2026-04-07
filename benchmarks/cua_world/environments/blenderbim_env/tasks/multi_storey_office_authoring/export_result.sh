#!/bin/bash
echo "=== Exporting multi_storey_office_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/office_authoring_result.json"

cat > /tmp/export_office_authoring.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/meridian_office.ifc"

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
        "n_storeys": 0,
        "storey_elevations": [],
        "n_walls": 0,
        "has_upper_floor": False,
        "has_second_floor": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Project name
        projects = ifc.by_type("IfcProject")
        project_name = projects[0].Name if projects else ""

        # Storeys
        storeys = ifc.by_type("IfcBuildingStorey")
        n_storeys = len(storeys)
        elevations = []
        for s in storeys:
            try:
                elev = float(s.Elevation) if s.Elevation is not None else 0.0
                elevations.append(elev)
            except Exception:
                pass
        elevations_sorted = sorted(elevations)

        # Upper floors: any storey elevation > 2.0 m (or > 2000 mm)
        # Account for both metre and millimetre project units
        max_elev = max(elevations) if elevations else 0.0
        # If max elevation > 100, assume mm units; convert to m for comparison
        if max_elev > 100:
            elevations_m = [e / 1000.0 for e in elevations]
        else:
            elevations_m = elevations

        has_upper_floor = any(e > 2.0 for e in elevations_m)
        has_second_floor = any(e > 5.5 for e in elevations_m)

        # Walls
        walls = ifc.by_type("IfcWall")
        n_walls = len(walls)

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": project_name or "",
            "n_storeys": n_storeys,
            "storey_elevations": elevations_sorted,
            "n_walls": n_walls,
            "has_upper_floor": has_upper_floor,
            "has_second_floor": has_second_floor,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": "",
            "n_storeys": 0,
            "storey_elevations": [],
            "n_walls": 0,
            "has_upper_floor": False,
            "has_second_floor": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_office_authoring.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"project_name":"","n_storeys":0,"n_walls":0,"has_upper_floor":false,"has_second_floor":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
