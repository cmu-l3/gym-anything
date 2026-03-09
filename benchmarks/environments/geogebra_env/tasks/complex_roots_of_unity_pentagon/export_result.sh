#!/bin/bash
# Export script for Roots of Unity task
set -o pipefail

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
    "task_start_time": 0,
    "task_end_time": 0,
    "has_unit_circle": false,
    "points_found": [],
    "has_polygon": false,
    "has_slider": false,
    "has_text": false,
    "xml_commands": [],
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

echo "=== Exporting Roots of Unity Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python to analyze the .ggb file structure
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/roots_of_unity.ggb"
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
    "has_unit_circle": False,
    "points_found": [],
    "has_polygon": False,
    "has_slider": False,
    "has_text": False,
    "xml_commands": []
}

# 1. Find the file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for any recently modified .ggb file
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
                construction = root.find('.//construction') or root

                # Extract commands for verification
                commands = []
                for cmd in root.iter('command'):
                    name = cmd.get('name')
                    if name:
                        commands.append(name)
                result["xml_commands"] = list(set(commands))

                # Check Elements
                points = []
                
                for elem in root.iter('element'):
                    etype = elem.get('type', '')
                    
                    # Check for Polygon
                    if etype == 'polygon':
                        result["has_polygon"] = True
                        
                    # Check for Text
                    if etype == 'text':
                        result["has_text"] = True
                        
                    # Check for Slider (numeric with animation step/interval)
                    if etype == 'numeric':
                        # Check for slider features
                        if elem.find('slider') is not None or elem.get('label') in ['θ', 'alpha', 'n']:
                            result["has_slider"] = True
                    
                    # Check for Circle (conic)
                    if etype == 'conic':
                        # Check coords/matrix if possible, or assume conic is the circle
                        # Unit circle x^2 + y^2 = 1 -> matrix diag(1, 1, -1)
                        matrix = elem.find('matrix')
                        if matrix is not None:
                            try:
                                a = float(matrix.get('A0', matrix.get('A', 0)))
                                c = float(matrix.get('A2', matrix.get('C', 0)))
                                f = float(matrix.get('A5', matrix.get('F', 0)))
                                # Just rough check for circle centered at origin
                                if abs(a - c) < 0.1 and abs(a) > 0.01:
                                    result["has_unit_circle"] = True
                            except:
                                pass
                        # Also check if defined by command Circle
                        cmd_parent = root.find(f".//command[@name='Circle']/output[@a0='{elem.get('label')}']")
                        if cmd_parent is not None:
                             result["has_unit_circle"] = True

                    # Extract Points
                    if etype == 'point':
                        coords = elem.find('coords')
                        if coords is not None:
                            try:
                                x = float(coords.get('x', 0))
                                y = float(coords.get('y', 0))
                                z = float(coords.get('z', 1))
                                if abs(z) > 1e-9:
                                    points.append((x/z, y/z))
                                else:
                                    points.append((x, y)) # Infinite point, unlikely for roots
                            except:
                                pass
                
                result["points_found"] = points

    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="