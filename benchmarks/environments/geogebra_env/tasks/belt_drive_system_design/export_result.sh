#!/bin/bash
# Export script for Belt Drive System Design task
set -o pipefail

# Ensure fallback result on any failure
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
    "circles_found": [],
    "numeric_values": [],
    "text_content": [],
    "commands_used": [],
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

echo "=== Exporting Belt Drive Design Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python to analyze the .ggb file structure
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/belt_drive.ggb"
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
    "circles_found": [],
    "numeric_values": [],
    "text_content": [],
    "commands_used": [],
    "segments_count": 0,
    "arcs_count": 0,
    "tangents_count": 0
}

# Find file
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
        mtime = os.path.getmtime(c)
        if TASK_START_TIME > 0 and int(mtime) >= TASK_START_TIME:
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
                
                # Extract commands
                result["commands_used"] = list(set(re.findall(r'<command name="([^"]+)"', xml_content)))
                
                # Parse XML for geometry
                try:
                    root = ET.fromstring(xml_content)
                    construction = root.find('.//construction')
                    
                    if construction is not None:
                        for elem in construction.findall('element'):
                            etype = elem.get('type', '')
                            label = elem.get('label', '')
                            
                            # Count geometry types
                            if etype == 'segment':
                                result["segments_count"] += 1
                            elif etype == 'arc' or etype == 'semicircle':
                                result["arcs_count"] += 1
                            elif etype == 'line':
                                # Check if it's a tangent (often created by Tangent command)
                                # But we'll rely on command check for "Tangent"
                                pass
                            
                            # Extract numeric values (angles, lengths)
                            if etype == 'numeric' or etype == 'angle':
                                val_elem = elem.find('value')
                                if val_elem is not None:
                                    try:
                                        val = float(val_elem.get('val', 0))
                                        result["numeric_values"].append({'label': label, 'value': val, 'type': etype})
                                    except:
                                        pass
                            
                            # Extract text
                            if etype == 'text':
                                # Start tag might contain text, or it's a value
                                # GeoGebra text often in <startPoint> or similar, but the content is usually not directly in attributes easily
                                # Regex is safer for text content in XML
                                pass
                            
                            # Extract Conics (Circles)
                            if etype == 'conic':
                                # Check if it's a circle
                                # GeoGebra circles usually have equation coefficients or center/radius
                                # Standard circle: x^2 + y^2 + ax + by + c = 0
                                # Or defined by center/radius command
                                coords = elem.find('coords') # coefficients of matrix representation
                                eigen = elem.find('eigenvectors') 
                                # Simpler: look for Circle command output
                                pass

                        # Regex approach for specific circle definitions is often more robust for verification scripts
                        # looking for <coords x="..." y="..." z="..."/> inside points
                        
                        # Find all points to check centers
                        points = []
                        for elem in construction.findall('element'):
                            if elem.get('type') == 'point':
                                coords = elem.find('coords')
                                if coords is not None:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z = float(coords.get('z', 1))
                                    if z != 0:
                                        points.append({'x': x/z, 'y': y/z})
                        
                        # Identify circles by command inputs usually
                        # But simpler: scan the command list for "Circle"
                        # And we need radii. 
                        # Let's extract values associated with "radius" if possible
                        # Or check if points (0,0) and (500,0) exist
                        
                        result["points_found"] = points

                except Exception as e:
                    result["xml_parse_error"] = str(e)

                # Regex for text content (labels, values)
                # GeoGebra text: val="..." inside <element type="text"> or similar, usually encoded
                # We will check numeric_values list which captures measured angles/distances
                
                # Check for specific "Tangent" command
                if "Tangent" in result["commands_used"]:
                    result["tangents_count"] += 1

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="