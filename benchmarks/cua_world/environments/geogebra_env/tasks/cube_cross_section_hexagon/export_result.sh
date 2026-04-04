#!/bin/bash
# Export script for Cube Hexagon Cross-Section task
set -o pipefail

# Fallback result creation
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_3d_view": false,
    "has_cube": false,
    "has_plane": false,
    "has_intersection": false,
    "area_text_found": false,
    "area_value": 0.0,
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Load utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Cube Hexagon Result ==="

# Final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Analyze GGB file using Python
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/cube_hexagon.ggb"
TASK_START_TIME = 0

try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "has_3d_view": False,
    "has_cube": False,
    "has_plane": False,
    "has_intersection": False,
    "area_text_found": False,
    "area_value": 0.0,
    "xml_commands": [],
    "text_elements": []
}

# Find file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check recent files
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
    mtime = os.path.getmtime(found_file)
    result["file_created_during_task"] = int(mtime) >= TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check for 3D View
                # usually indicated by <euclidianView3D> tag
                result["has_3d_view"] = "<euclidianView3D>" in xml_content

                # Parse XML for commands and elements
                root = ET.fromstring(xml_content)
                
                # Extract commands
                commands = []
                for cmd in root.findall(".//command"):
                    name = cmd.get("name")
                    if name:
                        commands.append(name)
                result["xml_commands"] = list(set(commands))

                # Check for Cube
                # Either 'Cube' command or substantial 3D point geometry
                has_cube_cmd = "Cube" in commands
                # Or check for 'prism' type elements which Cube generates
                has_prism = False
                for elem in root.findall(".//element"):
                    if elem.get("type") == "polyhedron":
                        has_prism = True
                        break
                result["has_cube"] = has_cube_cmd or has_prism

                # Check for Plane
                # Either 'Plane'/'PerpendicularPlane' command or plane element
                has_plane_cmd = any(c in commands for c in ["Plane", "PerpendicularPlane", "OrthogonalPlane"])
                has_plane_elem = False
                for elem in root.findall(".//element"):
                    if elem.get("type") == "plane":
                        has_plane_elem = True
                        break
                result["has_plane"] = has_plane_cmd or has_plane_elem

                # Check for Intersection
                # IntersectPath, IntersectRegion, or Intersect
                has_intersect = any(c in commands for c in ["Intersect", "IntersectPath", "IntersectRegion"])
                result["has_intersection"] = has_intersect

                # Extract Text/Area
                # Looking for a text element that contains a number near 5.196
                texts = []
                for elem in root.findall(".//element"):
                    if elem.get("type") == "text":
                        # Text value is often in val attribute or body
                        # GeoGebra stores text display string separate from value sometimes
                        # We try to extract any floating point numbers from text elements
                        # Also check the 'startPoint' which locates it in 3D
                        body = ""
                        # Try to find the text content. GeoGebra XML structure varies for text.
                        # Sometimes it's a value attribute, sometimes internal.
                        # We'll just regex the XML snippet for this element
                        elem_str = ET.tostring(elem, encoding='unicode')
                        texts.append(elem_str)
                
                result["text_elements"] = texts
                
                # Search for the area value (approx 5.196) in the whole file or text elements
                # Look for numbers like 5.19... or 5.20 or 3*sqrt(3)
                # Area of regular hexagon side sqrt(2) is 3*sqrt(3)/2 * (sqrt(2))^2 = 3*sqrt(3) ~ 5.196
                
                # We simply search for the numeric value in the XML content (annotations often store the value)
                # or in variables
                numbers = re.findall(r'val="([5]\.[12][0-9]*)"', xml_content)
                numbers += re.findall(r'>\s*([5]\.[12][0-9]*)\s*<', xml_content)
                
                found_area = False
                for n in numbers:
                    try:
                        val = float(n)
                        if 5.1 <= val <= 5.3:
                            result["area_value"] = val
                            result["area_text_found"] = True
                            found_area = True
                            break
                    except:
                        continue
                
                # Also check expression values (e.g. calculated variable)
                if not found_area:
                    # Look for expression values
                    for elem in root.findall(".//element"):
                        val = elem.get("value") # sometimes unused in XML
                        # but often <value val="5.196..."/> subtag
                        val_tag = elem.find("value")
                        if val_tag is not None:
                            v = val_tag.get("val")
                            try:
                                fv = float(v)
                                if 5.1 <= fv <= 5.3:
                                    result["area_value"] = fv
                                    result["area_text_found"] = True
                                    break
                            except:
                                pass

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

print("Analysis complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="