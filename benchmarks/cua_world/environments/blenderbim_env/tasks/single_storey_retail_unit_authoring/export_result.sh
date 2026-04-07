#!/bin/bash
echo "=== Exporting single_storey_retail_unit_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/retail_unit_result.json"

cat > /tmp/export_retail_unit.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/.local/lib/python3.11/site-packages')

ifc_path = "/home/ga/BIMProjects/retail_unit.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

if not os.path.exists(ifc_path):
    result = {
        "file_exists": False,
        "file_size_bytes": 0,
        "file_mtime": 0.0,
        "task_start": task_start,
        "file_newer_than_task_start": False,
        "ifc_schema": None,
        "wall_count": 0,
        "wall_names": [],
        "slab_count": 0,
        "slab_names": [],
        "door_count": 0,
        "door_names": [],
        "window_count": 0,
        "space_count": 0,
        "space_names": [],
        "space_long_names": [],
        "storey_count": 0,
        "storey_names": [],
        "building_count": 0,
        "site_count": 0,
        "project_name": None,
        "elements_in_storey": 0,
        "total_building_elements": 0,
        "error": "Output file not found"
    }
else:
    try:
        import ifcopenshell

        stat = os.stat(ifc_path)
        ifc = ifcopenshell.open(ifc_path)

        walls = list(ifc.by_type("IfcWall"))
        slabs = list(ifc.by_type("IfcSlab"))
        doors = list(ifc.by_type("IfcDoor"))
        windows = list(ifc.by_type("IfcWindow"))
        spaces = list(ifc.by_type("IfcSpace"))
        storeys = list(ifc.by_type("IfcBuildingStorey"))
        buildings = list(ifc.by_type("IfcBuilding"))
        sites = list(ifc.by_type("IfcSite"))
        projects = list(ifc.by_type("IfcProject"))

        # Count elements assigned to storeys
        elements_in_storey = 0
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            if hasattr(rel, 'RelatingStructure') and rel.RelatingStructure:
                if rel.RelatingStructure.is_a("IfcBuildingStorey"):
                    elements_in_storey += len(rel.RelatedElements or [])

        result = {
            "file_exists": True,
            "file_size_bytes": stat.st_size,
            "file_mtime": stat.st_mtime,
            "task_start": task_start,
            "file_newer_than_task_start": stat.st_mtime > task_start,
            "ifc_schema": ifc.schema,
            "wall_count": len(walls),
            "wall_names": [w.Name or '' for w in walls],
            "slab_count": len(slabs),
            "slab_names": [s.Name or '' for s in slabs],
            "door_count": len(doors),
            "door_names": [d.Name or '' for d in doors],
            "window_count": len(windows),
            "space_count": len(spaces),
            "space_names": [s.Name or '' for s in spaces],
            "space_long_names": [s.LongName or '' for s in spaces if hasattr(s, 'LongName')],
            "storey_count": len(storeys),
            "storey_names": [st.Name or '' for st in storeys],
            "building_count": len(buildings),
            "site_count": len(sites),
            "project_name": projects[0].Name if projects else None,
            "elements_in_storey": elements_in_storey,
            "total_building_elements": len(list(ifc.by_type("IfcBuildingElement"))),
            "error": None
        }
    except Exception as e:
        stat = os.stat(ifc_path)
        result = {
            "file_exists": True,
            "file_size_bytes": stat.st_size,
            "file_mtime": stat.st_mtime,
            "task_start": task_start,
            "file_newer_than_task_start": stat.st_mtime > task_start,
            "ifc_schema": None,
            "wall_count": 0,
            "wall_names": [],
            "slab_count": 0,
            "slab_names": [],
            "door_count": 0,
            "door_names": [],
            "window_count": 0,
            "space_count": 0,
            "space_names": [],
            "space_long_names": [],
            "storey_count": 0,
            "storey_names": [],
            "building_count": 0,
            "site_count": 0,
            "project_name": None,
            "elements_in_storey": 0,
            "total_building_elements": 0,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_retail_unit.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"wall_count":0,"slab_count":0,"door_count":0,"space_count":0,"task_start":0,"error":"No output from export script"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
