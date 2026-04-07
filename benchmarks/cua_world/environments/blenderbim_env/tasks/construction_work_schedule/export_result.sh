#!/bin/bash
echo "=== Exporting construction_work_schedule result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/work_schedule_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_work_schedule.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_construction_schedule.ifc"

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
        "n_schedules": 0,
        "n_tasks": 0,
        "n_task_times": 0,
        "n_assign_rels": 0,
        "n_assigned_elements": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Schedules
        schedules = ifc.by_type("IfcWorkSchedule")
        
        # Tasks
        tasks = ifc.by_type("IfcTask")
        
        # Durations (TaskTime)
        task_times = ifc.by_type("IfcTaskTime")
        valid_times = sum(1 for t in task_times if t.ScheduleDuration is not None)
        
        # Process Assignments
        rels = ifc.by_type("IfcRelAssignsToProcess")
        
        # Count unique building elements assigned
        assigned_elements = set()
        for rel in rels:
            if rel.RelatedObjects:
                for obj in rel.RelatedObjects:
                    if obj.is_a("IfcBuildingElement"):
                        assigned_elements.add(obj.id())
                        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_schedules": len(schedules),
            "n_tasks": len(tasks),
            "n_task_times": valid_times,
            "n_assign_rels": len(rels),
            "n_assigned_elements": len(assigned_elements),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_schedules": 0,
            "n_tasks": 0,
            "n_task_times": 0,
            "n_assign_rels": 0,
            "n_assigned_elements": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_work_schedule.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_schedules":0,"n_tasks":0,"n_task_times":0,"n_assign_rels":0,"n_assigned_elements":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"