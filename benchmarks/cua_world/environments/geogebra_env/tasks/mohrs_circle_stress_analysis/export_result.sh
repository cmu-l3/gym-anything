#!/bin/bash
# Export script for Mohr's Circle Stress Analysis
set -o pipefail

# Fallback mechanism
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "sliders_found": [],
    "points_found": 0,
    "circle_found": false,
    "intersections_found": false,
    "calibration_correct": false,
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Results ==="

# 1. Final Evidence
take_screenshot /tmp/task_final.png

# 2. Run Python Analysis
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/mohrs_circle.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "sliders_found": [],
    "points_found": 0,
    "circle_found": False,
    "intersections_found": False,
    "calibration_values": {},
    "principal_stresses": []
}

# Locate file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for recently created files
    candidates = sorted(
        glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True),
        key=os.path.getmtime, reverse=True
    )
    for c in candidates:
        if TASK_START_TIME > 0 and int(os.path.getmtime(c)) >= TASK_START_TIME:
            found_file = c
            break

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    mtime = os.path.getmtime(found_file)
    result["file_modified"] = int(mtime)
    result["file_created_during_task"] = int(mtime) >= TASK_START_TIME
    result["file_size"] = os.path.getsize(found_file)

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                root = ET.fromstring(xml_content)
                
                # Scan elements
                construction = root.find('construction') or root
                
                # Check Sliders (numeric elements)
                sliders = {}
                for elem in construction.findall(".//element[@type='numeric']"):
                    label = elem.get('label')
                    val_elem = elem.find('value')
                    if val_elem is not None:
                        val = float(val_elem.get('val', 0))
                        sliders[label] = val
                
                result["sliders_found"] = list(sliders.keys())
                result["calibration_values"] = sliders

                # Check Points
                points = []
                for elem in construction.findall(".//element[@type='point']"):
                    label = elem.get('label')
                    coords = elem.find('coords')
                    if coords is not None:
                        x = float(coords.get('x', 0))
                        y = float(coords.get('y', 0))
                        z = float(coords.get('z', 1))
                        if z != 0:
                            points.append({'label': label, 'x': x/z, 'y': y/z})
                result["points_found"] = len(points)
                
                # Check Circle (conic)
                # Look for conics that are likely circles (matrix representation or command)
                conics = construction.findall(".//element[@type='conic']")
                result["circle_found"] = len(conics) > 0
                
                # Check Intersections (Principal Stresses)
                # We expect points on the x-axis (y ~ 0) that match the principal stress values
                # If calibration is correct: 85 and -45
                on_axis_points = [p['x'] for p in points if abs(p['y']) < 0.1]
                result["principal_stresses"] = sorted(on_axis_points)
                
                # Check if "Intersect" command was used
                commands = re.findall(r'<command name="Intersect"', xml_content, re.IGNORECASE)
                if commands:
                    result["intersections_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export Complete"
cat /tmp/task_result.json