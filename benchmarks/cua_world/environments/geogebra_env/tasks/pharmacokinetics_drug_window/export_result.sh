#!/bin/bash
# Export script for Pharmacokinetics Drug Window task
set -o pipefail

# Error handling wrapper
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script failed to run or complete"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting PK Analysis Result ==="

# 1. Capture final state
take_screenshot /tmp/task_end_screenshot.png

# 2. Parse GeoGebra file using Python
# We extract the logic to Python for robust XML parsing
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import math
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/pk_analysis.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "task_end_time": int(time.time()),
    "has_bateman_function": False,
    "has_window_lines": False,
    "intersection_points_count": 0,
    "intersection_y_values": [],
    "duration_value": None,
    "variable_definitions": [],
    "xml_commands": []
}

# Locate file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for recent files
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
    result["file_size"] = os.path.getsize(found_file)
    mtime = os.path.getmtime(found_file)
    result["file_modified"] = int(mtime)
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Parse XML
                root = ET.fromstring(xml_content)
                
                # 1. Check for Bateman function structure
                # Looking for patterns like exp(-...x) - exp(-...x)
                # GeoGebra might store it as C(x) = ...
                has_exp_neg = "exp(-" in xml_content or "e^{-" in xml_content or "ℯ^{-" in xml_content
                # Check if it has two exponentials subtracted
                result["has_bateman_function"] = has_exp_neg and ("-" in xml_content)
                
                # 2. Check for Window Lines (y=5, y=12)
                # Elements of type 'line' with equation y=5
                lines_found = 0
                for elem in root.iter('element'):
                    if elem.get('type') == 'line':
                        # Check coords or equation
                        # Horizontal line y=k has coords (0, 1, -k) usually
                        coords = elem.find('coords')
                        if coords is not None:
                            y = float(coords.get('y', 0))
                            z = float(coords.get('z', 0))
                            # equation 0x + 1y - k = 0  => y = k
                            if y == 1.0 and (abs(z + 5.0) < 0.1 or abs(z + 12.0) < 0.1):
                                lines_found += 1
                result["has_window_lines"] = (lines_found >= 1) # At least lower bound is critical
                
                # 3. Check for Intersection Points
                # Points with y ~ 5.0
                intersections = []
                for elem in root.iter('element'):
                    if elem.get('type') == 'point':
                        coords = elem.find('coords')
                        if coords is not None:
                            # Homogeneous coords (x, y, z) -> (x/z, y/z)
                            cx = float(coords.get('x', 0))
                            cy = float(coords.get('y', 0))
                            cz = float(coords.get('z', 1))
                            if abs(cz) > 1e-6:
                                px = cx/cz
                                py = cy/cz
                                # Check if close to therapeutic threshold 5.0
                                if abs(py - 5.0) < 0.1:
                                    intersections.append(py)
                
                result["intersection_points_count"] = len(intersections)
                result["intersection_y_values"] = intersections
                
                # 4. Check for numeric duration calculation
                # Look for numeric elements with value around 9.22
                for elem in root.iter('element'):
                    if elem.get('type') == 'numeric':
                        val = elem.find('value')
                        if val is not None:
                            v = float(val.get('val', 0))
                            if abs(v - 9.22) < 0.5:
                                result["duration_value"] = v
                
                # 5. Check for variables D, V, ka, ke
                vars_found = []
                for elem in root.iter('element'):
                    label = elem.get('label', '')
                    if label in ['D', 'V', 'ka', 'ke']:
                        vars_found.append(label)
                result["variable_definitions"] = vars_found

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."