#!/bin/bash
echo "=== Exporting electrical_small_power_authoring result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/electrical_result.json"

cat > /tmp/export_electrical.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_electrical.ifc"

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
        "n_boards": 0,
        "n_outlets": 0,
        "n_systems": 0,
        "n_assigned_boards": 0,
        "n_assigned_outlets": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        # Retrieve instances
        boards = list(ifc.by_type("IfcDistributionBoard"))
        outlets = list(ifc.by_type("IfcOutlet"))
        
        # IfcSystem matches IfcSystem and its subtypes (like IfcDistributionSystem)
        systems = list(ifc.by_type("IfcSystem"))

        assigned_board_ids = set()
        assigned_outlet_ids = set()

        # Check system assignments
        # IfcRelAssignsToGroup links RelatedObjects to a RelatingGroup (the system)
        group_rels = list(ifc.by_type("IfcRelAssignsToGroup"))
        for rel in group_rels:
            # Check if the group is an electrical system
            if rel.RelatingGroup and rel.RelatingGroup.is_a("IfcSystem"):
                for obj in (rel.RelatedObjects or []):
                    if obj.is_a("IfcDistributionBoard"):
                        assigned_board_ids.add(obj.id())
                    elif obj.is_a("IfcOutlet"):
                        assigned_outlet_ids.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boards": len(boards),
            "n_outlets": len(outlets),
            "n_systems": len(systems),
            "n_assigned_boards": len(assigned_board_ids),
            "n_assigned_outlets": len(assigned_outlet_ids),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boards": 0,
            "n_outlets": 0,
            "n_systems": 0,
            "n_assigned_boards": 0,
            "n_assigned_outlets": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_electrical.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_boards":0,"n_outlets":0,"n_systems":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"