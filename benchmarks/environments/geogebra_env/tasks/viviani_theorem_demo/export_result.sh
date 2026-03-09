#!/bin/bash
# Export script for Viviani's Theorem task
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": false,
    "triangle_valid": false,
    "point_inside": false,
    "num_distance_commands": 0,
    "has_text": false,
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

echo "=== Exporting Viviani's Theorem Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python for analysis of the .ggb (zip) file
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET
import math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/viviani_theorem.ggb"
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
    "triangle_valid": False,
    "triangle_side_length": 0,
    "point_inside": False,
    "num_distance_commands": 0,
    "has_text": False,
    "xml_commands": [],
    "points": [],
    "segments": []
}

# Find file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for recent .ggb files
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
    result["file_created_during_task"] = int(mtime) >= TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Basic regex counts
                result["num_distance_commands"] = len(re.findall(r'<command name="Distance"', xml_content, re.IGNORECASE))
                result["has_text"] = bool(re.search(r'<element type="text"', xml_content, re.IGNORECASE))
                
                # Extract commands for debug
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                # XML Parsing for geometry validation
                try:
                    root = ET.fromstring(xml_content)
                    construction = root.find('.//construction') or root
                    
                    # Extract Points
                    points = []
                    for elem in construction.findall('element'):
                        if elem.get('type') == 'point':
                            label = elem.get('label', '')
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z = float(coords.get('z', 1))
                                    if abs(z) > 1e-9:
                                        points.append({'label': label, 'x': x/z, 'y': y/z})
                                except:
                                    pass
                    result["points"] = points

                    # Validate Triangle (A, B, C)
                    # We look for 3 points that form an equilateral triangle with side approx 6
                    # Specifically near (0,0) and (6,0)
                    base_points = [p for p in points if abs(p['y']) < 0.5] # Points near y=0
                    top_points = [p for p in points if p['y'] > 4.0] # Points near y=5.2

                    if len(base_points) >= 2 and len(top_points) >= 1:
                        # Check side lengths
                        p1 = base_points[0]
                        p2 = base_points[1]
                        # Find the top point that forms triangle
                        p3 = top_points[0]
                        
                        d1 = math.hypot(p2['x']-p1['x'], p2['y']-p1['y'])
                        d2 = math.hypot(p3['x']-p2['x'], p3['y']-p2['y'])
                        d3 = math.hypot(p1['x']-p3['x'], p1['y']-p3['y'])
                        
                        avg_side = (d1+d2+d3)/3.0
                        result["triangle_side_length"] = avg_side
                        
                        # Equilateral check: sides within 5% of each other and close to 6
                        if abs(d1-6.0) < 0.5 and abs(d1-d2) < 0.5 and abs(d1-d3) < 0.5:
                            result["triangle_valid"] = True
                            
                            # Check for interior point
                            # Simple bounding box check is usually enough given the task constraints
                            # But let's check if there is a point roughly inside
                            # Centroid is around (3, 1.7)
                            for p in points:
                                if p == p1 or p == p2 or p == p3: continue
                                # Check if point is roughly inside (y > 0 and y < 5.2 and x > 0 and x < 6)
                                if 0.1 < p['y'] < 5.1 and 0.1 < p['x'] < 5.9:
                                    result["point_inside"] = True
                                    break

                except Exception as e:
                    result["xml_parse_error"] = str(e)

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="