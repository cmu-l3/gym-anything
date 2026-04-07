#!/bin/bash
echo "=== Exporting project_stakeholder_actor_assignment result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/stakeholder_result.json"

cat > /tmp/export_stakeholders.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_stakeholders.ifc"

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
        "has_karlsruhe": False,
        "has_architektur": False,
        "has_klarglas": False,
        "klarglas_actor_assigned": False,
        "klarglas_windows_assigned": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Check Organizations
        orgs = list(ifc.by_type("IfcOrganization"))
        has_karlsruhe = False
        has_architektur = False
        has_klarglas = False
        
        for org in orgs:
            name = (org.Name or "").lower()
            if "karlsruhe" in name:
                has_karlsruhe = True
            if "architektur" in name:
                has_architektur = True
            if "klarglas" in name:
                has_klarglas = True

        # 2. Check Actor Assignments
        actor_assignments = list(ifc.by_type("IfcRelAssignsToActor"))
        
        klarglas_actor_assigned = False
        klarglas_windows_assigned = 0
        
        for rel in actor_assignments:
            if not rel.RelatingActor:
                continue
            
            # Unpack the actual organization from the actor wrapper
            the_actor = rel.RelatingActor.TheActor
            org_name = ""
            if the_actor:
                if the_actor.is_a("IfcOrganization"):
                    org_name = (the_actor.Name or "").lower()
                elif the_actor.is_a("IfcPersonAndOrganization"):
                    if the_actor.TheOrganization:
                        org_name = (the_actor.TheOrganization.Name or "").lower()

            if "klarglas" in org_name:
                klarglas_actor_assigned = True
                
                # Count IfcWindow elements in RelatedObjects
                if rel.RelatedObjects:
                    for obj in rel.RelatedObjects:
                        if obj.is_a("IfcWindow"):
                            klarglas_windows_assigned += 1
                
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "has_karlsruhe": has_karlsruhe,
            "has_architektur": has_architektur,
            "has_klarglas": has_klarglas,
            "klarglas_actor_assigned": klarglas_actor_assigned,
            "klarglas_windows_assigned": klarglas_windows_assigned,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "has_karlsruhe": False,
            "has_architektur": False,
            "has_klarglas": False,
            "klarglas_actor_assigned": False,
            "klarglas_windows_assigned": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_stakeholders.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"