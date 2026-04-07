#!/bin/bash
echo "=== Exporting stair_vertical_circulation result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/stair_model_result.json"

cat > /tmp/export_stair_model.py << 'PYEOF'
import sys
import json
import os

# Ensure ifcopenshell can be imported
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/hillcrest_stairs.ifc"

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
        "has_upper_floor": False,
        "n_stairs": 0,
        "n_stair_flights": 0,
        "n_railings": 0,
        "n_proxies": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Project name
        projects = ifc.by_type("IfcProject")
        project_name = projects[0].Name if projects and hasattr(projects[0], 'Name') else ""

        # Storeys and elevations
        storeys = ifc.by_type("IfcBuildingStorey")
        n_storeys = len(storeys)
        
        elevations = []
        for s in storeys:
            try:
                # Handle varying schema implementations
                if hasattr(s, 'Elevation') and s.Elevation is not None:
                    elev = float(s.Elevation)
                    elevations.append(elev)
            except Exception:
                pass

        # Detect upper floors (Elevation > 2.5m or > 2500mm)
        max_elev = max(elevations) if elevations else 0.0
        
        # Normalize to meters if units are clearly in mm
        if max_elev > 100:
            elevations_m = [e / 1000.0 for e in elevations]
        else:
            elevations_m = elevations

        has_upper_floor = any(e >= 2.5 for e in elevations_m)

        # Vertical circulation elements
        n_stairs = len(ifc.by_type("IfcStair"))
        n_flights = len(ifc.by_type("IfcStairFlight"))
        n_railings = len(ifc.by_type("IfcRailing"))
        
        # Anti-gaming check: IfcBuildingElementProxy count
        n_proxies = len(ifc.by_type("IfcBuildingElementProxy"))

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": project_name or "",
            "n_storeys": n_storeys,
            "storey_elevations": elevations,
            "has_upper_floor": has_upper_floor,
            "n_stairs": n_stairs,
            "n_stair_flights": n_flights,
            "n_railings": n_railings,
            "n_proxies": n_proxies,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "project_name": "",
            "n_storeys": 0,
            "has_upper_floor": False,
            "n_stairs": 0,
            "n_stair_flights": 0,
            "n_railings": 0,
            "n_proxies": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_stair_model.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"