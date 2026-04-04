#!/bin/bash
# Export script for Linear Transformation Eigenvector Visualization task
set -o pipefail

# Trap to ensure a result file is always generated
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_unit_square": false,
    "has_apply_matrix": false,
    "has_transformed_poly": false,
    "has_eigenvector_1": false,
    "has_eigenvector_2": false,
    "has_text": false,
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Linear Transformation Result ==="

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze the GGB file using Python
# We embed the python script to avoid dependency issues on the host
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import math
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/linear_transform_eigen.ggb"
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
    "task_start_time": TASK_START_TIME,
    "task_end_time": int(time.time()),
    "has_unit_square": False,
    "has_apply_matrix": False,
    "has_transformed_poly": False,
    "has_eigenvector_1": False,  # (1,1)
    "has_eigenvector_2": False,  # (1,-1)
    "has_text": False,
    "xml_commands": [],
    "points": []
}

# Locate file (handle potential name variations or exact path)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for any GGB file created recently
    import glob
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
    mtime = int(os.path.getmtime(found_file))
    result["file_modified"] = mtime
    result["file_created_during_task"] = mtime >= TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Parse XML
                root = ET.fromstring(xml_content)
                
                # 1. Check for ApplyMatrix command
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))
                result["has_apply_matrix"] = any(cmd.lower() == 'applymatrix' for cmd in result["xml_commands"])
                
                # 2. Extract Points
                points = []
                # Find all elements of type point
                for elem in root.iter('element'):
                    if elem.get('type') == 'point':
                        coords = elem.find('coords')
                        if coords is not None:
                            try:
                                x = float(coords.get('x', 0))
                                y = float(coords.get('y', 0))
                                z = float(coords.get('z', 1))
                                if abs(z) > 1e-6:
                                    points.append((x/z, y/z))
                                else:
                                    points.append((x, y)) # Infinite point / vector direction
                            except:
                                pass
                result["points"] = points

                # 3. Check for Unit Square Points (0,0), (1,0), (0,1), (1,1)
                # Allow small tolerance
                unit_square_target = {(0,0), (1,0), (0,1), (1,1)}
                found_unit_pts = 0
                for tx, ty in unit_square_target:
                    for px, py in points:
                        if abs(px - tx) < 0.1 and abs(py - ty) < 0.1:
                            found_unit_pts += 1
                            break
                result["has_unit_square"] = (found_unit_pts >= 4)
                
                # 4. Check for Transformed Points (0,0), (2,1), (1,2), (3,3)
                transformed_target = {(2,1), (1,2), (3,3)}
                found_trans_pts = 0
                for tx, ty in transformed_target:
                    for px, py in points:
                        if abs(px - tx) < 0.1 and abs(py - ty) < 0.1:
                            found_trans_pts += 1
                            break
                result["has_transformed_poly"] = (found_trans_pts >= 3) # (0,0) overlaps with unit square

                # 5. Check for Vectors (Eigenvectors)
                # Vectors in GeoGebra are elements of type="vector"
                vectors = []
                for elem in root.iter('element'):
                    if elem.get('type') == 'vector':
                        coords = elem.find('coords')
                        if coords is not None:
                            try:
                                x = float(coords.get('x', 0))
                                y = float(coords.get('y', 0))
                                z = float(coords.get('z', 0)) # vectors usually have z=0 for direction
                                vectors.append((x, y))
                            except:
                                pass
                
                # Check Vector 1: Direction (1,1) -> slope 1
                for vx, vy in vectors:
                    if abs(vx) > 0.01 and abs(vy) > 0.01:
                        slope = vy / vx
                        if abs(slope - 1.0) < 0.1 and vx > 0 and vy > 0:
                             result["has_eigenvector_1"] = True

                # Check Vector 2: Direction (1,-1) -> slope -1
                for vx, vy in vectors:
                    if abs(vx) > 0.01 and abs(vy) > 0.01:
                        slope = vy / vx
                        if abs(slope - (-1.0)) < 0.1: # Allow direction (1,-1) or (-1,1)
                             result["has_eigenvector_2"] = True

                # 6. Check for Text
                text_elems = re.findall(r'<element type="text"', xml_content)
                result["has_text"] = len(text_elems) > 0

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="