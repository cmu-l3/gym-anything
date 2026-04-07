#!/bin/bash
echo "=== Exporting ifc_quality_schema_remediation result ==="

source /workspace/scripts/task_utils.sh || true

take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/quality_remediation_result.json"

cat > /tmp/export_quality_remediation.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_remediated.ifc"
contaminated_path = "/home/ga/IFCModels/fzk_contaminated.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

# Load the original names for comparison
original_names = {}
try:
    with open("/tmp/fzk_original_names.json") as f:
        original_names = json.load(f)
except Exception:
    pass

original_space_names = set(v for v in original_names.get("original_space_names", {}).values() if v and v != "Room")
original_wall_names = set(v for v in original_names.get("original_wall_names", {}).values() if v and v != "Wall")

EMPTY_RESULT = {
    "file_exists": False,
    "file_mtime": 0.0,
    "task_start": task_start,
    "site_has_coordinates": False,
    "site_lat": None,
    "site_lon": None,
    "building_has_address": False,
    "building_town": None,
    "building_country": None,
    "n_spaces": 0,
    "spaces_all_named": False,
    "unique_space_names": 0,
    "spaces_generic": 0,
    "n_walls": 0,
    "walls_all_named": False,
    "unique_wall_names": 0,
    "walls_generic": 0
}

if not os.path.exists(ifc_path):
    result = EMPTY_RESULT
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Check IfcSite coordinates
        site_has_coords = False
        site_lat = None
        site_lon = None
        for site in ifc.by_type("IfcSite"):
            if site.RefLatitude and site.RefLongitude:
                site_has_coords = True
                site_lat = list(site.RefLatitude)
                site_lon = list(site.RefLongitude)
            break

        # Check IfcBuilding address
        bldg_has_address = False
        bldg_town = None
        bldg_country = None
        for bldg in ifc.by_type("IfcBuilding"):
            addr = bldg.BuildingAddress
            if addr:
                bldg_has_address = True
                bldg_town = getattr(addr, "Town", None)
                bldg_country = getattr(addr, "Country", None)
            break

        # Check IfcSpace names
        spaces = list(ifc.by_type("IfcSpace"))
        space_names = [s.Name or "" for s in spaces]
        spaces_generic = sum(1 for n in space_names if n.strip().lower() in ("room", ""))
        unique_space_names = len(set(n for n in space_names if n.strip().lower() not in ("room", "")))
        spaces_all_named = spaces_generic == 0 and len(spaces) > 0

        # Check IfcWall names
        walls = list(ifc.by_type("IfcWall")) + list(ifc.by_type("IfcWallStandardCase"))
        seen = set()
        unique_walls_list = []
        for w in walls:
            if w.id() not in seen:
                seen.add(w.id())
                unique_walls_list.append(w)
        wall_names = [w.Name or "" for w in unique_walls_list]
        walls_generic = sum(1 for n in wall_names if n.strip().lower() in ("wall", ""))
        unique_wall_names = len(set(n for n in wall_names if n.strip().lower() not in ("wall", "")))
        walls_all_named = walls_generic == 0 and len(unique_walls_list) > 0

        # Anti-gaming: make sure the output is not the contaminated file
        # (check if it has the same errors as the contaminated model)
        is_contaminated = (not site_has_coords) and (not bldg_has_address) and spaces_generic > 0

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "site_has_coordinates": site_has_coords,
            "site_lat": site_lat,
            "site_lon": site_lon,
            "building_has_address": bldg_has_address,
            "building_town": bldg_town,
            "building_country": bldg_country,
            "n_spaces": len(spaces),
            "spaces_all_named": spaces_all_named,
            "unique_space_names": unique_space_names,
            "spaces_generic": spaces_generic,
            "n_walls": len(unique_walls_list),
            "walls_all_named": walls_all_named,
            "unique_wall_names": unique_wall_names,
            "walls_generic": walls_generic,
            "appears_contaminated": is_contaminated
        }

    except Exception as e:
        result = dict(EMPTY_RESULT)
        result.update({"file_exists": True,
                        "file_mtime": os.path.getmtime(ifc_path),
                        "error": str(e)})

print("RESULT:" + json.dumps(result, default=str))
PYEOF

/opt/blender/blender --background --python /tmp/export_quality_remediation.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"task_start":0,"site_has_coordinates":false,"building_has_address":false,"spaces_generic":0,"walls_generic":0,"error":"Export produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
