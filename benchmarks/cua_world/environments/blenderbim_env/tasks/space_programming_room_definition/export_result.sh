#!/bin/bash
echo "=== Exporting space_programming_room_definition result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/space_programming_result.json"

cat > /tmp/export_space_programming.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_spaces.ifc"

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
        "n_spaces": 0,
        "n_named_spaces": 0,
        "n_typed_spaces": 0,
        "n_storeys_with_spaces": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell

        ifc = ifcopenshell.open(ifc_path)

        # 1. Count IfcSpace entities
        spaces = list(ifc.by_type("IfcSpace"))
        n_spaces = len(spaces)

        # 2. Count named spaces (checking LongName specifically per instructions)
        named_spaces = [s for s in spaces if getattr(s, "LongName", None) and str(s.LongName).strip()]
        n_named_spaces = len(named_spaces)

        # 3. Count typed spaces (PredefinedType == 'SPACE')
        typed_spaces = [s for s in spaces if getattr(s, "PredefinedType", None) == "SPACE"]
        n_typed_spaces = len(typed_spaces)

        # 4. Check storey containment
        storeys_with_spaces = set()
        
        # Method A: Assigned via IfcRelContainedInSpatialStructure
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            container = rel.RelatingStructure
            if container and container.is_a("IfcBuildingStorey"):
                for obj in (rel.RelatedElements or []):
                    if obj.is_a("IfcSpace"):
                        storeys_with_spaces.add(container.id())

        # Method B: Decomposed under a storey via IfcRelAggregates
        for rel in ifc.by_type("IfcRelAggregates"):
            parent = rel.RelatingObject
            if parent and parent.is_a("IfcBuildingStorey"):
                for child in (rel.RelatedObjects or []):
                    if child.is_a("IfcSpace"):
                        storeys_with_spaces.add(parent.id())

        n_storeys_with_spaces = len(storeys_with_spaces)

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_spaces": n_spaces,
            "n_named_spaces": n_named_spaces,
            "n_typed_spaces": n_typed_spaces,
            "n_storeys_with_spaces": n_storeys_with_spaces,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_spaces": 0,
            "n_named_spaces": 0,
            "n_typed_spaces": 0,
            "n_storeys_with_spaces": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_space_programming.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"n_spaces":0,"n_named_spaces":0,"n_typed_spaces":0,"n_storeys_with_spaces":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"