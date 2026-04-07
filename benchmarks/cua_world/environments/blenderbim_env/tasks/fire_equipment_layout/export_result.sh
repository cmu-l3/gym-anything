#!/bin/bash
echo "=== Exporting fire_equipment_layout result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/fire_equipment_result.json"

cat > /tmp/export_fire_equipment.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_fire_equipment.ifc"

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
        "n_alarms": 0,
        "n_alarms_smoke": 0,
        "n_terminals": 0,
        "n_terminals_extinguisher": 0,
        "n_alarms_contained": 0,
        "n_terminals_contained": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        alarms = list(ifc.by_type("IfcAlarm"))
        terminals = list(ifc.by_type("IfcFireSuppressionTerminal"))

        n_alarms = len(alarms)
        n_terminals = len(terminals)

        n_alarms_smoke = sum(1 for a in alarms if a.PredefinedType == "SMOKE")
        n_terminals_extinguisher = sum(1 for t in terminals if t.PredefinedType == "FIREEXTINGUISHER")

        # Check spatial containment
        contained_ids = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            if rel.RelatingStructure and rel.RelatingStructure.is_a("IfcBuildingStorey"):
                for elem in (rel.RelatedElements or []):
                    contained_ids.add(elem.id())

        n_alarms_contained = sum(1 for a in alarms if a.id() in contained_ids)
        n_terminals_contained = sum(1 for t in terminals if t.id() in contained_ids)

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_alarms": n_alarms,
            "n_alarms_smoke": n_alarms_smoke,
            "n_terminals": n_terminals,
            "n_terminals_extinguisher": n_terminals_extinguisher,
            "n_alarms_contained": n_alarms_contained,
            "n_terminals_contained": n_terminals_contained,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_alarms": 0,
            "n_alarms_smoke": 0,
            "n_terminals": 0,
            "n_terminals_extinguisher": 0,
            "n_alarms_contained": 0,
            "n_terminals_contained": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_fire_equipment.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"