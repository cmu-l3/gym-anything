#!/bin/bash
# Export result for measure_3d_zygomatic_width task

echo "=== Exporting measure_3d_zygomatic_width result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_PATH="/home/ga/Documents/skull_3d_measure.inv3"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Parse the InVesalius project file (.inv3 is a tar.gz containing plists)
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import time

inv3_path = "/home/ga/Documents/skull_3d_measure.inv3"
task_start = int(os.environ.get("TASK_START", 0))

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "valid_project": False,
    "has_surface": False,
    "measurement_count": 0,
    "measurements": [],
    "valid_measurement_found": False
}

if os.path.isfile(inv3_path):
    result["file_exists"] = True
    mtime = os.path.getmtime(inv3_path)
    if mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["valid_project"] = True
            
            # Check for surfaces (proof of 3D generation)
            # Surfaces usually have corresponding .vtp files or entries in plists
            members = t.getnames()
            surface_files = [m for m in members if m.endswith('.vtp') or 'surface' in m]
            if len(surface_files) > 0:
                result["has_surface"] = True

            # Parse measurements
            if "measurements.plist" in members:
                f = t.extractfile("measurements.plist")
                if f:
                    try:
                        meas_data = plistlib.load(f)
                        # measurements.plist is a dict of measurements
                        for key, m in meas_data.items():
                            val = float(m.get("value", 0))
                            # Check if 3D type if available, otherwise assume linear
                            m_type = m.get("type", "Linear") 
                            
                            result["measurements"].append({
                                "value_mm": val,
                                "type": m_type,
                                "color": m.get("colour", [])
                            })
                    except Exception as e:
                        result["parse_error"] = str(e)
            
            result["measurement_count"] = len(result["measurements"])

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="