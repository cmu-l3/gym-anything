#!/bin/bash
# Export script for Cross Product 3D Visualization
set -o pipefail

# Ensure a result file is always created
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_3d_view": false,
    "has_cross_command": false,
    "num_vectors": 0,
    "has_polygon": false,
    "has_annotation": false,
    "correct_result_vector": false,
    "error": "Export script failed or crashed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Cross Product Result ==="

# 1. Capture final state visual evidence
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis script
# We use Python here because parsing XML (GeoGebra format) in bash is fragile
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
EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/cross_product_3d.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result_data = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "timestamp": int(time.time()),
    "has_3d_view": False,
    "has_cross_command": False,
    "num_vectors": 0,
    "has_polygon": False,
    "has_annotation": False,
    "correct_result_vector": False,
    "found_vectors": [],
    "xml_commands": []
}

# Find the file (check specific path first, then recent files)
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
    result_data["file_found"] = True
    result_data["file_path"] = found_file
    mtime = os.path.getmtime(found_file)
    result_data["file_created_during_task"] = int(mtime) >= TASK_START_TIME
    
    try:
        # GeoGebra files are ZIP archives containing geogebra.xml
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # 1. Check for 3D View usage
                # euclidianView3D tag indicates 3D view settings were saved
                if 'euclidianView3D' in xml_content or 'type="point3d"' in xml_content:
                    result_data["has_3d_view"] = True
                
                # 2. Extract Commands
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result_data["xml_commands"] = list(set(commands))
                
                if 'Cross' in commands:
                    result_data["has_cross_command"] = True
                
                if 'Polygon' in commands:
                    result_data["has_polygon"] = True
                else:
                    # Fallback: check for polygon element type directly
                    if re.search(r'<element type="polygon"', xml_content, re.IGNORECASE):
                        result_data["has_polygon"] = True
                
                # 3. Check for Annotation (Text)
                if re.search(r'<element type="text"', xml_content, re.IGNORECASE):
                    result_data["has_annotation"] = True
                
                # 4. Parse Elements for Vectors and Coordinates
                # We need to parse XML properly to get coordinates
                try:
                    root = ET.fromstring(xml_content)
                    
                    # Search for 3D vectors/points
                    construction = root.find(".//construction")
                    if construction is not None:
                        for elem in construction.findall("element"):
                            etype = elem.get("type")
                            coords = elem.find("coords")
                            
                            if etype == "vector3d" or etype == "vector":
                                if coords is not None:
                                    x = float(coords.get("x", 0))
                                    y = float(coords.get("y", 0))
                                    z = float(coords.get("z", 0))
                                    result_data["num_vectors"] += 1
                                    
                                    vec_info = {"x": x, "y": y, "z": z, "label": elem.get("label")}
                                    result_data["found_vectors"].append(vec_info)
                                    
                                    # Check if this matches expected result (2, -7, -6)
                                    # Tolerance 0.1
                                    if (abs(x - 2.0) < 0.1 and 
                                        abs(y - (-7.0)) < 0.1 and 
                                        abs(z - (-6.0)) < 0.1):
                                        result_data["correct_result_vector"] = True
                                        
                except Exception as e:
                    print(f"XML parsing error: {e}")
                    # Fallback regex if XML parsing fails
                    if re.search(r'x\s*=\s*2', xml_content) and re.search(r'y\s*=\s*-7', xml_content):
                         # Very weak check, but better than nothing
                         pass

    except Exception as e:
        result_data["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result_data, f, indent=4)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="