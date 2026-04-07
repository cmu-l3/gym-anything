#!/bin/bash
echo "=== Exporting rainwater_harvesting_system_modeling result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/rainwater_system_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_rainwater_system.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_rainwater_system.ifc"

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
        "n_walls": 0,
        "n_tanks": 0,
        "n_pumps": 0,
        "n_pipes": 0,
        "n_valid_systems": 0,
        "n_assigned_elements": 0,
        "system_names": [],
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Count elements
        walls = list(ifc.by_type("IfcWall"))
        tanks = list(ifc.by_type("IfcTank"))
        pumps = list(ifc.by_type("IfcPump"))
        pipes = list(ifc.by_type("IfcPipeSegment"))
        
        # Check for systems matching keywords
        keywords = ["rainwater", "harvest", "reclaimed", "non-potable"]
        valid_systems = []
        
        for sys_ent in ifc.by_type("IfcSystem"):
            name = (sys_ent.Name or "").lower()
            if any(kw in name for kw in keywords):
                valid_systems.append(name)
                
        # Count elements assigned to these valid systems
        assigned_elements = set()
        for rel in ifc.by_type("IfcRelAssignsToGroup"):
            group = rel.RelatingGroup
            if group and group.is_a("IfcSystem"):
                name = (group.Name or "").lower()
                if any(kw in name for kw in keywords):
                    for obj in (rel.RelatedObjects or []):
                        assigned_elements.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": len(walls),
            "n_tanks": len(tanks),
            "n_pumps": len(pumps),
            "n_pipes": len(pipes),
            "n_valid_systems": len(valid_systems),
            "n_assigned_elements": len(assigned_elements),
            "system_names": valid_systems,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_walls": 0,
            "n_tanks": 0,
            "n_pumps": 0,
            "n_pipes": 0,
            "n_valid_systems": 0,
            "n_assigned_elements": 0,
            "system_names": [],
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_rainwater_system.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_walls":0,"n_tanks":0,"n_pumps":0,"n_pipes":0,"n_valid_systems":0,"n_assigned_elements":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"