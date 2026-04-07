#!/bin/bash
echo "=== Exporting cost_schedule_from_takeoff result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/cost_schedule_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_cost_schedule.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_cost_schedule.ifc"

# Read task start timestamp
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
        "cost_schedules": 0,
        "cost_items": 0,
        "cost_values": 0,
        "element_quantities": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "cost_schedules": len(ifc.by_type("IfcCostSchedule")),
            "cost_items": len(ifc.by_type("IfcCostItem")),
            "cost_values": len(ifc.by_type("IfcCostValue")),
            "element_quantities": len(ifc.by_type("IfcElementQuantity")),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "cost_schedules": 0,
            "cost_items": 0,
            "cost_values": 0,
            "element_quantities": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_cost_schedule.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"cost_schedules":0,"cost_items":0,"cost_values":0,"element_quantities":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"
