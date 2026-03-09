#!/bin/bash
# Export script for Circle Inversion Explorer task
set -o pipefail

# Ensure fallback result on any failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_created_during_task": false,
    "has_circle_radius_3": false,
    "has_reflect_circle": false,
    "has_line": false,
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

echo "=== Exporting Circle Inversion Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python for robust XML analysis of the .ggb (zip) file
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/circle_inversion.ggb"
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
    "has_circle_radius_3": False,
    "has_reflect_circle": False,
    "has_line": False,
    "has_text": False,
    "xml_commands": [],
    "conics": [],
    "points": []
}

# Find file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check recently modified .ggb files
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
                
                # Extract commands for basic debugging
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))
                
                root = ET.fromstring(xml_content)
                
                # 1. Identify Conics (Circles)
                # We need to find the inversion circle (radius 3 at 0,0)
                # In GeoGebra XML, conics are often defined by equation or command
                # We look for a Circle command or a conic element with specific coefficients
                # Simplest check: Is there a command "Circle" with radius 3?
                
                # Check command inputs
                circle_labels = []
                for cmd in root.findall(".//command[@name='Circle']"):
                    # Check input arguments
                    inp = cmd.find("input")
                    if inp is not None:
                        # Case: Circle(Point, Radius)
                        # We might see a1="3" if radius is literal, or a number object
                        # This is hard to parse perfectly without symbolic engine
                        # So we assume if Circle command exists, we check the resulting element
                        pass
                    
                    # Store output label
                    out = cmd.find("output")
                    if out is not None:
                        for attr in out.attrib:
                            if attr.startswith("a"):
                                circle_labels.append(out.attrib[attr])

                # Check elements for type="conic"
                for elem in root.findall(".//element[@type='conic']"):
                    label = elem.attrib.get('label')
                    
                    # Check coords/equation if possible. 
                    # For x^2 + y^2 = 9, the matrix is diag(1, 1, -9)
                    # GeoGebra XML stores matrix in <coords xx="1" yy="1" zz="-9" ... />
                    coords = elem.find("coords")
                    if coords is not None:
                        xx = float(coords.get('xx', 0))
                        yy = float(coords.get('yy', 0))
                        zz = float(coords.get('zz', 0))
                        
                        # x^2 + y^2 - 9 = 0  => xx=1, yy=1, zz=-9
                        # Allow scaling
                        if abs(xx - yy) < 0.01 and abs(xx) > 0.001:
                            r_squared = abs(zz / xx)
                            if abs(r_squared - 9.0) < 0.5:
                                result["has_circle_radius_3"] = True
                                if label: circle_labels.append(label)

                # 2. Check for Reflect command using a circle
                # We look for <command name="Reflect"> <input a0="Object" a1="Mirror"/>
                # a1 should be one of our circle labels
                reflect_circles = []
                for cmd in root.findall(".//command[@name='Reflect']"):
                    inp = cmd.find("input")
                    if inp is not None:
                        mirror = inp.get('a1')
                        if mirror and mirror in circle_labels:
                            result["has_reflect_circle"] = True
                        
                        # Also accept if we didn't identify the circle label but the mirror implies a conic
                        # (Hard to verify without full label map, but "c" is common default)
                        if mirror == 'c' or mirror == 'd':
                            # Heuristic: if we saw a circle command earlier, this is likely valid
                            reflect_circles.append(mirror)
                
                if not result["has_reflect_circle"] and len(reflect_circles) > 0 and result["has_circle_radius_3"]:
                     # Be generous if we found a circle and a reflection using a likely label
                     result["has_reflect_circle"] = True

                # 3. Check for Line element (not passing through origin)
                # Lines are type="line". <coords x="..." y="..." z="..."/> implies ax + by + c = 0
                # Passes through origin if z (constant term c) is close to 0
                for elem in root.findall(".//element[@type='line']"):
                    coords = elem.find("coords")
                    if coords is not None:
                        z = float(coords.get('z', 0))
                        if abs(z) > 0.1: # Non-zero constant term => not through origin
                            result["has_line"] = True

                # 4. Check for Text
                text_elems = root.findall(".//element[@type='text']")
                if len(text_elems) > 0:
                    result["has_text"] = True

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="