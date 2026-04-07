#!/bin/bash
echo "=== Exporting elevator_retrofit_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/elevator_retrofit_result.json"

# ── Create Python script to parse IFC and verify ──────────────────────────
cat > /tmp/export_elevator.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_elevator_retrofit.ifc"

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
        "n_doors": 0,
        "n_transport_elements": 0,
        "has_elevator_type": False,
        "has_capacity_prop": False,
        "is_contained": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        import ifcopenshell.util.element

        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Door count
        doors = ifc.by_type("IfcDoor")
        n_doors = len(doors)

        # 2. Transport elements
        transport_elements = ifc.by_type("IfcTransportElement")
        n_transport = len(transport_elements)

        has_elevator_type = False
        has_capacity_prop = False
        is_contained = False

        for te in transport_elements:
            # Check PredefinedType
            if te.PredefinedType == "ELEVATOR":
                has_elevator_type = True
            
            # Check Properties for 'Capacity'
            psets = ifcopenshell.util.element.get_psets(te)
            for pset_name, props in psets.items():
                for prop_name, prop_val in props.items():
                    if prop_name and "capacity" in prop_name.lower():
                        has_capacity_prop = True
            
            # Check Spatial Containment
            container = ifcopenshell.util.element.get_container(te)
            if container:
                is_contained = True

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_doors": n_doors,
            "n_transport_elements": n_transport,
            "has_elevator_type": has_elevator_type,
            "has_capacity_prop": has_capacity_prop,
            "is_contained": is_contained,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_doors": 0,
            "n_transport_elements": 0,
            "has_elevator_type": False,
            "has_capacity_prop": False,
            "is_contained": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run script headlessly with Blender's bundled Python ───────────────────
/opt/blender/blender --background --python /tmp/export_elevator.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output from export"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"