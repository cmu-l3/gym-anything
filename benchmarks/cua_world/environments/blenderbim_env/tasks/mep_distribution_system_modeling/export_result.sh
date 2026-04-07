#!/bin/bash
echo "=== Exporting mep_distribution_system_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/mep_system_result.json"

cat > /tmp/export_mep.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_mep_services.ifc"

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
        "n_systems": 0,
        "system_names": [],
        "n_ducts": 0,
        "n_pipes": 0,
        "n_grouped_mep": 0,
        "n_walls": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # Count systems
        systems = list(ifc.by_type("IfcDistributionSystem"))
        n_systems = len(systems)
        system_names = [s.Name for s in systems if s.Name]

        # Count MEP elements
        ducts = list(ifc.by_type("IfcDuctSegment"))
        pipes = list(ifc.by_type("IfcPipeSegment"))
        n_ducts = len(ducts)
        n_pipes = len(pipes)

        # Count assigned elements
        grouped_mep = set()
        for rel in ifc.by_type("IfcRelAssignsToGroup"):
            if rel.RelatingGroup and rel.RelatingGroup.is_a("IfcDistributionSystem"):
                for obj in (rel.RelatedObjects or []):
                    if obj.is_a("IfcDuctSegment") or obj.is_a("IfcPipeSegment"):
                        grouped_mep.add(obj.id())

        n_grouped_mep = len(grouped_mep)

        # Sanity check: preserved architecture
        walls = list(ifc.by_type("IfcWall"))
        n_walls = len(walls)

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_systems": n_systems,
            "system_names": system_names,
            "n_ducts": n_ducts,
            "n_pipes": n_pipes,
            "n_grouped_mep": n_grouped_mep,
            "n_walls": n_walls,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_systems": 0,
            "system_names": [],
            "n_ducts": 0,
            "n_pipes": 0,
            "n_grouped_mep": 0,
            "n_walls": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_mep.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_systems":0,"n_ducts":0,"n_pipes":0,"n_grouped_mep":0,"n_walls":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"