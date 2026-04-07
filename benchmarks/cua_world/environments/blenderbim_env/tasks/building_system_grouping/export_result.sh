#!/bin/bash
echo "=== Exporting building_system_grouping result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/group_result.json"

cat > /tmp/export_grouping.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_fm_groups.ifc"

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
        "n_groups": 0,
        "group_names": [],
        "n_relationships": 0,
        "n_assigned_elements": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Count groups (also include IfcSystem and IfcZone as they inherit from IfcGroup)
        groups = list(ifc.by_type("IfcGroup"))
        group_names = [g.Name for g in groups if g.Name]

        # Relationships
        rels = list(ifc.by_type("IfcRelAssignsToGroup"))
        n_relationships = len(rels)

        # Unique elements assigned
        assigned_element_ids = set()
        for rel in rels:
            for obj in (rel.RelatedObjects or []):
                assigned_element_ids.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_groups": len(groups),
            "group_names": group_names,
            "n_relationships": n_relationships,
            "n_assigned_elements": len(assigned_element_ids),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_groups": 0,
            "group_names": [],
            "n_relationships": 0,
            "n_assigned_elements": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_grouping.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_groups":0,"group_names":[],"n_relationships":0,"n_assigned_elements":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"