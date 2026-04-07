#!/bin/bash
echo "=== Exporting av_it_infrastructure_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/av_it_result.json"

cat > /tmp/export_av_it.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_smart_home.ifc"

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
        "task_start": task_start,
        "av_appliances": [],
        "comms_appliances": []
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        def get_appliance_data(instances):
            data = []
            for inst in instances:
                # Check for physical representation and placement
                has_geom = bool(getattr(inst, 'Representation', None) and getattr(inst, 'ObjectPlacement', None))
                
                # Check for spatial containment in an IfcBuildingStorey
                contained = False
                for rel in getattr(inst, 'ContainedInStructure', []):
                    if rel.is_a('IfcRelContainedInSpatialStructure'):
                        if getattr(rel, 'RelatingStructure', None) and rel.RelatingStructure.is_a('IfcBuildingStorey'):
                            contained = True
                            break

                data.append({
                    "name": inst.Name or "",
                    "predefined_type": inst.PredefinedType or "",
                    "has_geometry": has_geom,
                    "contained_in_storey": contained
                })
            return data

        avs = ifc.by_type("IfcAudioVisualAppliance")
        comms = ifc.by_type("IfcCommunicationsAppliance")

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "av_appliances": get_appliance_data(avs),
            "comms_appliances": get_appliance_data(comms)
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "task_start": task_start,
            "error": str(e),
            "av_appliances": [],
            "comms_appliances": []
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_av_it.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"av_appliances":[],"comms_appliances":[],"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"