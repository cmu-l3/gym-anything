#!/bin/bash
echo "=== Exporting iot_sensor_network_modeling result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before extracting data
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/sensor_network_result.json"

# ── Write the extraction Python script ────────────────────────────────────
cat > /tmp/export_sensors.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_iot_sensors.ifc"

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
        "n_sensors": 0,
        "n_sensor_types": 0,
        "predefined_types_used": [],
        "n_contained_sensors": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        sensors = ifc.by_type("IfcSensor")
        sensor_types = ifc.by_type("IfcSensorType")
        
        # Determine PredefinedTypes used (either directly on occurrence or via type)
        ptypes = set()
        for s in sensors:
            if s.PredefinedType and s.PredefinedType != "NOTDEFINED":
                ptypes.add(s.PredefinedType)
            elif hasattr(s, "IsTypedBy") and s.IsTypedBy:
                for rel in s.IsTypedBy:
                    if rel.is_a("IfcRelDefinesByType") and rel.RelatingType and rel.RelatingType.is_a("IfcSensorType"):
                        pt = rel.RelatingType.PredefinedType
                        if pt and pt != "NOTDEFINED":
                            ptypes.add(pt)
                            
        # Spatial Containment check
        contained_elements = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            if rel.RelatedElements:
                for el in rel.RelatedElements:
                    contained_elements.add(el.id())
                    
        contained_sensors = sum(1 for s in sensors if s.id() in contained_elements)
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_sensors": len(sensors),
            "n_sensor_types": len(sensor_types),
            "predefined_types_used": list(ptypes),
            "n_contained_sensors": contained_sensors,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_sensors": 0,
            "n_sensor_types": 0,
            "predefined_types_used": [],
            "n_contained_sensors": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run headless script with bundled ifcopenshell ─────────────────────────
/opt/blender/blender --background --python /tmp/export_sensors.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export fails ──────────────────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_sensors":0,"n_sensor_types":0,"predefined_types_used":[],"n_contained_sensors":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"