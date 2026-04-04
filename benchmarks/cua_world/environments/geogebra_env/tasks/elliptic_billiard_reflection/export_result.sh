#!/bin/bash
# Export script for Elliptic Billiard Reflection task
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_created_during_task": false,
    "has_ellipse": false,
    "has_foci": false,
    "has_tangent": false,
    "has_angles": false,
    "error": "Export script failed to run completion analysis"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Utilities
take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }

echo "=== Exporting Task Result ==="

# 1. Capture final visual state
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis script
# We use Python here to parse the GeoGebra XML properly, which is cleaner than bash grep
python3 << 'PYEOF'
import os
import sys
import zipfile
import json
import time
import glob
import re
import math
import xml.etree.ElementTree as ET

# Configuration
EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/elliptic_billiard.ggb"
TASK_START_TIME = 0

try:
    with open("/tmp/task_start_time", "r") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_created_during_task": False,
    "has_ellipse": False,
    "ellipse_details": "",
    "foci_found": [],
    "has_foci": False,
    "has_tangent": False,
    "has_point_on_path": False,
    "has_segments": False,
    "has_angles": False,
    "has_text": False,
    "xml_commands": [],
    "xml_elements": []
}

# Locate file (exact path or search)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Fallback: find newest .ggb file
    candidates = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
    if candidates:
        found_file = max(candidates, key=os.path.getmtime)

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    mtime = os.path.getmtime(found_file)
    result["file_size"] = os.path.getsize(found_file)
    
    # Check if created/modified during task
    if TASK_START_TIME > 0 and mtime >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # Analyze GeoGebra XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Basic Regex Checks for quick validation
                result["xml_commands"] = list(set(re.findall(r'<command name="([^"]+)"', xml_content)))
                
                # Detailed Parsing
                root = ET.fromstring(xml_content)
                construction = root.find(".//construction")
                
                if construction is not None:
                    # 1. Check for Ellipse
                    # Can be via Command "Ellipse" or Element type "conic"
                    for elem in construction.findall("element"):
                        etype = elem.get("type", "")
                        result["xml_elements"].append(etype)
                        
                        if etype == "conic":
                            # Check equation coefficients if available (x^2/25 + y^2/16 = 1)
                            # GeoGebra often stores implicit form: xx^2 + yy^2 + ...
                            # We'll rely on the command or existence of conic for now
                            result["has_ellipse"] = True
                            
                        if etype == "point":
                            # Check coords for foci (-3,0) and (3,0)
                            coords = elem.find("coords")
                            if coords is not None:
                                try:
                                    x = float(coords.get("x", 0)) / float(coords.get("z", 1))
                                    y = float(coords.get("y", 0)) / float(coords.get("z", 1))
                                    if (abs(x - 3.0) < 0.2 and abs(y) < 0.2) or (abs(x + 3.0) < 0.2 and abs(y) < 0.2):
                                        result["foci_found"].append((x, y))
                                except:
                                    pass
                                    
                    # 2. Check for Tangent
                    if "Tangent" in result["xml_commands"]:
                        result["has_tangent"] = True
                        
                    # 3. Check for Angle measurements
                    if "Angle" in result["xml_commands"] or "angle" in result["xml_elements"]:
                        result["has_angles"] = True
                        
                    # 4. Check for Text
                    if "text" in result["xml_elements"]:
                        result["has_text"] = True
                        
                    # 5. Check for Point on Path (Point command with input)
                    # OR just checking if we have enough points (F1, F2, P)
                    if result["xml_elements"].count("point") >= 3:
                        result["has_point_on_path"] = True

                    # 6. Verify Foci count
                    # We expect at least 2 points near +/- 3
                    if len(result["foci_found"]) >= 2:
                        result["has_foci"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/task_result.json"