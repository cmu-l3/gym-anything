#!/bin/bash
echo "=== Exporting qto_base_quantities result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/qto_result.json"

cat > /tmp/export_qto.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_qto_enriched.ifc"

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
        "walls_qto": 0,
        "doors_qto": 0,
        "windows_qto": 0,
        "slabs_qto": 0,
        "nonzero_elements": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        import ifcopenshell.util.element
        
        ifc = ifcopenshell.open(ifc_path)
        
        walls = ifc.by_type("IfcWall")
        doors = ifc.by_type("IfcDoor")
        windows = ifc.by_type("IfcWindow")
        slabs = ifc.by_type("IfcSlab")
        
        def check_qto(elements, qto_name):
            count = 0
            nonzero_elements = 0
            for e in elements:
                try:
                    # get_psets returns both IfcPropertySet and IfcElementQuantity data
                    psets = ifcopenshell.util.element.get_psets(e)
                    if qto_name in psets:
                        count += 1
                        qto_dict = psets[qto_name]
                        has_nonzero = False
                        for k, v in qto_dict.items():
                            if isinstance(v, (int, float)) and v > 0:
                                has_nonzero = True
                        if has_nonzero:
                            nonzero_elements += 1
                except Exception:
                    pass
            return count, nonzero_elements
            
        walls_qto, w_nz = check_qto(walls, "Qto_WallBaseQuantities")
        doors_qto, d_nz = check_qto(doors, "Qto_DoorBaseQuantities")
        wins_qto, win_nz = check_qto(windows, "Qto_WindowBaseQuantities")
        slabs_qto, s_nz = check_qto(slabs, "Qto_SlabBaseQuantities")
        
        total_nonzero = w_nz + d_nz + win_nz + s_nz
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "walls_qto": walls_qto,
            "doors_qto": doors_qto,
            "windows_qto": wins_qto,
            "slabs_qto": slabs_qto,
            "nonzero_elements": total_nonzero,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "walls_qto": 0,
            "doors_qto": 0,
            "windows_qto": 0,
            "slabs_qto": 0,
            "nonzero_elements": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_qto.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"walls_qto":0,"doors_qto":0,"windows_qto":0,"slabs_qto":0,"nonzero_elements":0,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"