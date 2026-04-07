#!/bin/bash
echo "=== Exporting equipment_maintenance_scheduling result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/maintenance_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_maintenance.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_fm_maintenance.ifc"

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
        "n_boilers": 0,
        "n_pumps": 0,
        "n_schedules": 0,
        "n_tasks": 0,
        "boiler_linked": False,
        "pump_linked": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Count elements
        boilers = ifc.by_type("IfcBoiler")
        pumps = ifc.by_type("IfcPump")
        schedules = ifc.by_type("IfcWorkSchedule")
        tasks = ifc.by_type("IfcTask")
        
        boiler_linked = False
        pump_linked = False
        
        # Traverse IfcRelAssignsToProcess to find equipment assigned to tasks
        process_rels = ifc.by_type("IfcRelAssignsToProcess")
        for rel in process_rels:
            process = rel.RelatingProcess
            # RelatingProcess should be the task
            if process and process.is_a("IfcTask"):
                related_objects = rel.RelatedObjects
                if related_objects:
                    for obj in related_objects:
                        if obj.is_a("IfcBoiler"):
                            boiler_linked = True
                        if obj.is_a("IfcPump"):
                            pump_linked = True

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boilers": len(boilers),
            "n_pumps": len(pumps),
            "n_schedules": len(schedules),
            "n_tasks": len(tasks),
            "boiler_linked": boiler_linked,
            "pump_linked": pump_linked,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_boilers": 0,
            "n_pumps": 0,
            "n_schedules": 0,
            "n_tasks": 0,
            "boiler_linked": False,
            "pump_linked": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_maintenance.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_boilers":0,"n_pumps":0,"n_schedules":0,"n_tasks":0,"boiler_linked":false,"pump_linked":false,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"