#!/bin/bash
# Export script for Inscribed Angle Theorem Demo
set -o pipefail

# Always generate a result file
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
    "task_start_time": 0,
    "task_end_time": 0,
    "has_circle": false,
    "num_points_on_circle": 0,
    "num_angles": 0,
    "has_text": false,
    "angle_values": [],
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Inscribed Angle Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python analysis script
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

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/inscribed_angle.ggb"
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
    "has_circle": False,
    "circle_radius": 0,
    "circle_center": [0, 0],
    "num_points": 0,
    "num_points_on_circle": 0,
    "num_angles": 0,
    "angle_values": [],
    "has_text": False,
    "xml_commands": []
}

# Find the file (check expected location first, then search)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for any recent .ggb file
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
                
                # Parse XML
                root = ET.fromstring(xml_content)
                construction = root.find('.//construction')
                
                if construction is not None:
                    # Check for Circle
                    # GeoGebra stores conics. Circles usually have matrix rep or specific commands.
                    # Simple check: look for element type="conic" or command name="Circle"
                    
                    # 1. Count elements
                    points = []
                    angles = []
                    
                    for elem in construction.findall('element'):
                        etype = elem.get('type', '')
                        elabel = elem.get('label', '')
                        
                        if etype == 'point':
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z = float(coords.get('z', 1))
                                    if abs(z) > 1e-6:
                                        points.append({'label': elabel, 'x': x/z, 'y': y/z})
                                    else:
                                        # Point at infinity?
                                        points.append({'label': elabel, 'x': x, 'y': y, 'infinity': True})
                                except:
                                    pass
                                    
                        elif etype == 'angle':
                            # Angle values are often stored in 'value' attribute or computed
                            # We can try to get the 'val' from the element tag if present (depends on version)
                            # Or check the command inputs
                            val_attr = elem.find('value')
                            if val_attr is not None:
                                try:
                                    val = float(val_attr.get('val', 0))
                                    # GeoGebra angles are usually radians internally in XML?
                                    # Often stored as degrees in UI but value attribute is radians.
                                    # Let's assume radians and convert for the verifier, 
                                    # OR just store what we find. 
                                    # Actually, let's store degrees: val * 180 / pi
                                    angles.append({'label': elabel, 'radians': val, 'degrees': val * 180.0 / 3.14159})
                                except:
                                    pass
                            else:
                                angles.append({'label': elabel, 'value': 'unknown'})

                        elif etype == 'text':
                            result["has_text"] = True

                        elif etype == 'conic':
                            # Check if it's a circle
                            # Circles usually generated by Circle command
                            pass

                    result["num_points"] = len(points)
                    result["num_angles"] = len(angles)
                    result["angle_values"] = [a.get('degrees', 0) for a in angles]
                    
                    # Check for circle command explicitly
                    commands = re.findall(r'<command name="([^"]+)"', xml_content)
                    result["xml_commands"] = list(set(commands))
                    
                    has_circle_cmd = 'Circle' in result["xml_commands"]
                    
                    # Check for points on circle (distance from origin approx 3)
                    points_on_circle = 0
                    for p in points:
                        dist = math.sqrt(p['x']**2 + p['y']**2)
                        if abs(dist - 3.0) < 0.1:
                            points_on_circle += 1
                            
                    # Refine Circle check: 
                    # If we found points at distance 3 from origin, highly likely circle is there
                    # OR if Circle command exists
                    result["has_circle"] = has_circle_cmd or (points_on_circle >= 2) # relaxed check
                    result["num_points_on_circle"] = points_on_circle

    except Exception as e:
        result["error"] = str(e)

# Write result to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json