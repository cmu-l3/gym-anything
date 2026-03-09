#!/bin/bash
# Export script for Surveying Resection task
set -o pipefail

# Fallback for result file creation
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_created_during_task": false,
    "landmarks_found": 0,
    "solution_found": false,
    "circles_found": 0,
    "angles_found": 0,
    "error": "Export script failed to complete"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Surveying Resection Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python analysis script
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

# Configuration
EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/resection_solution.ggb"
LANDMARKS = {
    "A": (-300, 200),
    "B": (100, 500),
    "C": (400, -100)
}
EXPECTED_P = (6.64, -225.56)
LANDMARK_TOL = 2.0  # slightly loose for float precision
SOLUTION_TOL = 5.0
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
    "landmarks_found_count": 0,
    "landmarks_status": {"A": False, "B": False, "C": False},
    "solution_found": False,
    "solution_coords": None,
    "circles_found": 0,
    "angles_found": 0,
    "xml_commands": [],
    "all_points": []
}

# 1. Locate File
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for recent .ggb files
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

    # 2. Parse GeoGebra XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Basic counters
                result["circles_found"] = len(re.findall(r'<element type="conic"', xml_content)) 
                # Note: arcs might show up as conicPart
                result["circles_found"] += len(re.findall(r'<element type="conicpart"', xml_content))
                result["angles_found"] = len(re.findall(r'<element type="angle"', xml_content))
                
                # Extract commands
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                # Parse points for detailed geometric verification
                root = ET.fromstring(xml_content)
                construction = root.find('.//construction')
                
                points = []
                if construction is not None:
                    for elem in construction.findall('element'):
                        if elem.get('type') == 'point':
                            label = elem.get('label', '')
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z = float(coords.get('z', 1))
                                    # Homogeneous coordinates conversion
                                    if abs(z) > 1e-9:
                                        rx, ry = x/z, y/z
                                        points.append({'label': label, 'x': rx, 'y': ry})
                                except:
                                    pass
                
                result["all_points"] = points

                # 3. Verify Landmarks
                for name, (lx, ly) in LANDMARKS.items():
                    # Check if any point is close to this landmark
                    for p in points:
                        dist = math.hypot(p['x'] - lx, p['y'] - ly)
                        if dist <= LANDMARK_TOL:
                            result["landmarks_status"][name] = True
                            break
                
                result["landmarks_found_count"] = sum(1 for v in result["landmarks_status"].values() if v)

                # 4. Verify Solution P
                # Check if any point is close to expected P, EXCLUDING landmarks
                # (Sometimes A, B, C are intersections too, we want the NEW point)
                best_dist = float('inf')
                solution_pt = None
                
                ex, ey = EXPECTED_P
                for p in points:
                    # Skip if it's one of the landmarks
                    is_landmark = False
                    for lx, ly in LANDMARKS.values():
                        if math.hypot(p['x'] - lx, p['y'] - ly) < LANDMARK_TOL:
                            is_landmark = True
                            break
                    if is_landmark:
                        continue
                        
                    dist = math.hypot(p['x'] - ex, p['y'] - ey)
                    if dist < best_dist:
                        best_dist = dist
                        solution_pt = p

                if best_dist <= SOLUTION_TOL:
                    result["solution_found"] = True
                    result["solution_coords"] = solution_pt

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="