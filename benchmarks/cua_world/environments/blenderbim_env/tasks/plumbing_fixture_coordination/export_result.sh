#!/bin/bash
echo "=== Exporting plumbing_fixture_coordination result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/plumbing_result.json"

# Write the export Python script
cat > /tmp/export_plumbing.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_plumbing.ifc"

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
        "n_terminals": 0,
        "has_toilet": False,
        "has_sink": False,
        "has_bath": False,
        "n_contained": 0,
        "predefined_types": [],
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        terminals = list(ifc.by_type("IfcSanitaryTerminal"))
        
        # Build set of all elements that are spatially contained in any storey
        contained_ids = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            elements = getattr(rel, "RelatedElements", []) or []
            for obj in elements:
                if hasattr(obj, "id"):
                    contained_ids.add(obj.id())
                    
        has_toilet = False
        has_sink = False
        has_bath = False
        n_contained = 0
        predefined_types = []
        
        for t in terminals:
            ptype = getattr(t, "PredefinedType", "NOTDEFINED") or "NOTDEFINED"
            predefined_types.append(str(ptype))
            
            if ptype in ("WCSEAT", "TOILETPAN"):
                has_toilet = True
            elif ptype in ("WASHHANDBASIN", "SINK"):
                has_sink = True
            elif ptype in ("BATH", "SHOWER"):
                has_bath = True
                
            if t.id() in contained_ids:
                n_contained += 1

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_terminals": len(terminals),
            "has_toilet": has_toilet,
            "has_sink": has_sink,
            "has_bath": has_bath,
            "n_contained": n_contained,
            "predefined_types": predefined_types,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_terminals": 0,
            "has_toilet": False,
            "has_sink": False,
            "has_bath": False,
            "n_contained": 0,
            "predefined_types": [],
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# Run via blender --background to access bundled ifcopenshell
/opt/blender/blender --background --python /tmp/export_plumbing.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# Fallback if export produced no output
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_terminals":0,"has_toilet":false,"has_sink":false,"has_bath":false,"n_contained":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"