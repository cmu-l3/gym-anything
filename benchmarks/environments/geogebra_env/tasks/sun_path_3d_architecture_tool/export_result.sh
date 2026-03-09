#!/bin/bash
# Export script for Sun Path 3D Architecture Tool
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_3d_view": false,
    "num_3d_objects": 0,
    "found_constants": [],
    "has_rotation": false,
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

echo "=== Exporting Sun Path Result ==="

# 1. Take final screenshot (critical for VLM)
take_screenshot /tmp/task_final.png

# 2. Run Python Analysis
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/seattle_sun_path.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "file_path": "",
    "has_3d_view": False,
    "num_3d_objects": 0,
    "num_circles": 0,
    "found_constants": [],
    "has_rotation": False,
    "xml_commands": [],
    "has_correct_paths": False,
    "timestamp": int(time.time())
}

# Find file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for recent files
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
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME
    
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check for 3D View
                # euclidianView3D tag indicates 3D view is active/configured
                if '<euclidianView3D' in xml:
                    result["has_3d_view"] = True
                
                # Count 3D objects (conic3d, quadric, etc.)
                conic3d = len(re.findall(r'<element type="conic3d"', xml))
                quadric = len(re.findall(r'<element type="quadric"', xml))
                # Parametric curves in 3D often use curvecartesian
                curve3d = len(re.findall(r'<element type="curvecartesian3d"', xml))
                
                result["num_3d_objects"] = conic3d + quadric + curve3d
                result["num_circles"] = conic3d  # Approximation
                
                # Extract commands
                commands = re.findall(r'<command name="([^"]+)"', xml)
                result["xml_commands"] = list(set(commands))
                
                # Check for Rotate command (key for tilting)
                if 'Rotate' in result["xml_commands"]:
                    result["has_rotation"] = True
                
                # Search for key constants
                # Latitude: 47.6, Co-lat: 42.4, Obliquity: 23.44 (or 23.4, 23.5)
                # We search in the whole XML text (values, definitions)
                constants_to_find = [47.6, 42.4, 23.44, 23.45, 23.4]
                found = []
                for c in constants_to_find:
                    # Regex for number with boundaries or within tags
                    if re.search(fr'["=>\s]{c}["<\s]', xml) or re.search(fr'val="{c}"', xml):
                        found.append(c)
                result["found_constants"] = list(set(found))
                
                # Check for correct paths logic
                # Ideally: 3 circles/curves and rotation or 3d view
                if result["num_3d_objects"] >= 3 or (len(result["xml_commands"]) >= 3 and result["has_3d_view"]):
                    result["has_correct_paths"] = True

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Export complete."
cat /tmp/task_result.json