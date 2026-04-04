#!/bin/bash
# Export script for Bicycle Geometry Trail Calculator task
set -o pipefail

# Ensure fallback result on any failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
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

echo "=== Exporting Bicycle Geometry Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python for robust geometric analysis of the .ggb file
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/bicycle_trail.ggb"
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
    "xml_valid": False,
    "circles": [],
    "lines": [],
    "segments": [],
    "texts": [],
    "numeric_values": [],
    "has_radius_370": False,
    "has_angle_67": False,
    "has_offset_44": False,
    "measured_trail": 0.0
}

# Find the file
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
                result["xml_valid"] = True
                
                # Parse XML
                root = ET.fromstring(xml_content)
                construction = root.find('.//construction')
                
                # Extract Elements
                for elem in construction.findall('element'):
                    etype = elem.get('type', '')
                    label = elem.get('label', '')
                    
                    # Circles (Wheel)
                    if etype == 'conic':
                        # GeoGebra stores conics as matrix coefficients or specific params
                        # We look for circle radius in coords or command
                        # Often stored as eigenvals/vecs or direct equation
                        # Simpler: check command inputs if possible, or look for 'val' attribute
                        val = float(elem.find('value').get('val', 0)) if elem.find('value') is not None else 0
                        # For circle x^2 + y^2 = r^2, val is sometimes related to r
                        # Better approach: check commands or coords
                        pass
                        
                    # Lines (Ground, Steering Axis)
                    if etype == 'line':
                        coords = elem.find('coords')
                        if coords is not None:
                            # ax + by + c = 0
                            x = float(coords.get('x', 0))
                            y = float(coords.get('y', 0))
                            z = float(coords.get('z', 0))
                            # Calculate angle from horizontal: atan2(x, -y) or similar depending on normal
                            # Normal vector is (x, y). Slope of line is -x/y.
                            # Angle of line = atan(-x/y)
                            angle_deg = 0
                            if abs(y) > 1e-6:
                                angle_rad = math.atan(-x/y)
                                angle_deg = math.degrees(angle_rad)
                            elif abs(x) > 1e-6:
                                angle_deg = 90.0
                            
                            # Normalize angle to 0-180
                            angle_deg = abs(angle_deg)
                            result["lines"].append({"label": label, "angle": angle_deg, "coeffs": [x, y, z]})

                    # Segments (Measurements)
                    if etype == 'segment':
                         val = float(elem.find('value').get('val', 0)) if elem.find('value') is not None else 0
                         result["segments"].append({"label": label, "length": val})
                    
                    # Text (Annotations)
                    if etype == 'text':
                        # Check text content
                        # GeoGebra text often contains LaTeX or direct strings
                        # We need to look deeper into the element or the start string
                        # Actually text content is usually in the tag text if plain, or attributes
                        # Let's rely on finding numeric values in the text for "109"
                        pass

                # Extract Commands to find Circle Radius and other construction details
                # <command name="Circle"> <input a0="A" a1="370"/> </command>
                for cmd in construction.findall('command'):
                    name = cmd.get('name')
                    inp = cmd.find('input')
                    
                    if name == 'Circle':
                        # Check for radius 370
                        if inp is not None:
                            # attributes like a0, a1...
                            for key in inp.attrib:
                                val = inp.get(key)
                                if '370' in str(val):
                                    result["has_radius_370"] = True
                    
                    if name == 'Distance' or name == 'Segment':
                        # Check results of distance commands
                        output = cmd.find('output')
                        if output is not None:
                            out_label = output.get('a0')
                            # Find the value of this label in elements
                            for s in result["segments"]:
                                if s['label'] == out_label:
                                    if 107 < s['length'] < 111: # Rough check for trail
                                        result["measured_trail"] = s['length']

                # Post-process Lines for Angle 67
                # We expect one horizontal line (angle 0 or 180) -> Ground
                # And one line at ~67 degrees -> Steering Axis
                for l in result["lines"]:
                    a = l["angle"]
                    # Check for 67 degrees (or 180-67 = 113)
                    if abs(a - 67.0) < 1.0 or abs(a - 113.0) < 1.0:
                        result["has_angle_67"] = True

                # Check for offset 44
                # This is hard to check purely from XML without a full geometry engine
                # Heuristic: Check for a command Distance(Point, Line) = 44 or Circle(Point, 44)
                # Or check if any segment has length 44
                for s in result["segments"]:
                    if abs(s['length'] - 44.0) < 0.5:
                        result["has_offset_44"] = True
                
                # Scan XML for raw "44" in inputs
                if not result["has_offset_44"]:
                     if '44' in xml_content:
                         # Weak check, but better than nothing
                         result["has_offset_44"] = True

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="