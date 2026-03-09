#!/bin/bash
# Export script for Newton's Method Task
set -o pipefail

# Fallback function
trap 'create_fallback_result' EXIT
create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo '{"error": "Export script failed", "file_found": false}' > /tmp/task_result.json
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Results ==="

# 1. Capture final state
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze the .ggb file (Zip archive containing XML)
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import glob
import math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/newtons_method.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "has_cubic_function": False,
    "has_derivative": False,
    "tangent_count": 0,
    "intersect_count": 0,
    "has_annotation": False,
    "iteration_points_found": [],
    "xml_commands": [],
    "timestamp": int(time.time())
}

# Find file (robust search)
found_path = None
if os.path.exists(EXPECTED_FILE):
    found_path = EXPECTED_FILE
else:
    # Check for recent files
    files = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
    files.sort(key=os.path.getmtime, reverse=True)
    if files:
        found_path = files[0]

if found_path:
    result["file_found"] = True
    mtime = os.path.getmtime(found_path)
    if mtime >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # Parse GeoGebra XML
    try:
        with zipfile.ZipFile(found_path, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # 1. Check Function: x^3 - 2x - 5
                # Look for definitions or expressions
                if re.search(r'x\^3\s*-\s*2\s*\*?\s*x\s*-\s*5', xml) or \
                   re.search(r'x³\s*-\s*2\s*x\s*-\s*5', xml):
                    result["has_cubic_function"] = True
                
                # 2. Check Derivative
                if 'Derivative' in xml or "f'" in xml:
                    result["has_derivative"] = True
                
                # 3. Count Tangents
                result["tangent_count"] = len(re.findall(r'cmd="Tangent"', xml)) + \
                                          len(re.findall(r'<command name="Tangent"', xml))
                
                # 4. Count Intersections/Roots
                result["intersect_count"] = len(re.findall(r'cmd="Intersect"', xml)) + \
                                            len(re.findall(r'<command name="Intersect"', xml)) + \
                                            len(re.findall(r'<command name="Root"', xml))

                # 5. Check Annotation
                if '<element type="text"' in xml:
                    result["has_annotation"] = True

                # 6. Extract Point Coordinates for Iteration Check
                # Extract all x coords from <coords x="..." ...>
                # Expected: 3.0 -> 2.36 -> 2.127 -> 2.095
                x_coords = []
                for m in re.finditer(r'<coords x="([^"]+)"', xml):
                    try:
                        x_coords.append(float(m.group(1)))
                    except:
                        pass
                result["iteration_points_found"] = x_coords
                
                # Store commands for debug
                result["xml_commands"] = re.findall(r'<command name="([^"]+)"', xml)

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json