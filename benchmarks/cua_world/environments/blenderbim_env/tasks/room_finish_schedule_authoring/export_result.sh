#!/bin/bash
echo "=== Exporting room_finish_schedule_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/room_finishes_result.json"

# Write the Python script to extract space property sets using IFCOpenShell
cat > /tmp/export_room_finishes.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_room_finishes.ifc"

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
        "spaces_with_pset": 0,
        "timber_floors": 0,
        "tile_floors": 0,
        "paint_walls": 0,
        "plasterboard_ceilings": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        spaces_data = []
        for space in ifc.by_type("IfcSpace"):
            space_info = {"has_pset": False, "floor": "", "wall": "", "ceiling": ""}
            for rel in getattr(space, "IsDefinedBy", []):
                if rel.is_a("IfcRelDefinesByProperties"):
                    pdef = rel.RelatingPropertyDefinition
                    if pdef and pdef.is_a("IfcPropertySet") and pdef.Name == "Pset_SpaceCoveringRequirements":
                        space_info["has_pset"] = True
                        for prop in (pdef.HasProperties or []):
                            if prop.is_a("IfcPropertySingleValue") and prop.NominalValue is not None:
                                val = str(prop.NominalValue.wrappedValue).lower()
                                if prop.Name == "FloorCovering":
                                    space_info["floor"] = val
                                elif prop.Name == "WallCovering":
                                    space_info["wall"] = val
                                elif prop.Name == "CeilingCovering":
                                    space_info["ceiling"] = val
            
            if space_info["has_pset"]:
                spaces_data.append(space_info)

        timber_floors = sum(1 for s in spaces_data if "timber" in s["floor"])
        tile_floors = sum(1 for s in spaces_data if "tile" in s["floor"])
        paint_walls = sum(1 for s in spaces_data if "paint" in s["wall"])
        plasterboard_ceilings = sum(1 for s in spaces_data if "plasterboard" in s["ceiling"])

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "spaces_with_pset": len(spaces_data),
            "timber_floors": timber_floors,
            "tile_floors": tile_floors,
            "paint_walls": paint_walls,
            "plasterboard_ceilings": plasterboard_ceilings,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "spaces_with_pset": 0,
            "timber_floors": 0,
            "tile_floors": 0,
            "paint_walls": 0,
            "plasterboard_ceilings": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Execute the python script inside Blender's python environment to ensure ifcopenshell compatibility
/opt/blender/blender --background --python /tmp/export_room_finishes.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output from export script"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"