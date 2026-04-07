#!/bin/bash
echo "=== Exporting project_information_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/project_info_result.json"

cat > /tmp/export_project_info.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/riverside_hub.ifc"

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
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Project Info
        projects = ifc.by_type("IfcProject")
        project = projects[0] if projects else None
        project_name = getattr(project, "Name", "") if project else ""
        project_desc = getattr(project, "Description", "") if project else ""
        
        # Organizations
        orgs = ifc.by_type("IfcOrganization")
        org_names = [getattr(o, "Name", "") for o in orgs if getattr(o, "Name", "")]
        
        # Persons
        persons = ifc.by_type("IfcPerson")
        person_family_names = [getattr(p, "FamilyName", "") for p in persons if getattr(p, "FamilyName", "")]
        
        # Sites
        sites = ifc.by_type("IfcSite")
        site_names = [getattr(s, "Name", "") for s in sites if getattr(s, "Name", "")]
        
        # Buildings
        buildings = ifc.by_type("IfcBuilding")
        building_names = [getattr(b, "Name", "") for b in buildings if getattr(b, "Name", "")]
        
        # Addresses
        addresses = ifc.by_type("IfcPostalAddress")
        towns = [getattr(a, "Town", "") for a in addresses if getattr(a, "Town", "")]
        
        # Elements Check (to ensure they didn't just save an empty model)
        walls = ifc.by_type("IfcWall")
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "project_name": project_name or "",
            "project_desc": project_desc or "",
            "org_names": org_names,
            "person_family_names": person_family_names,
            "site_names": site_names,
            "building_names": building_names,
            "towns": towns,
            "n_walls": len(walls)
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_project_info.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"