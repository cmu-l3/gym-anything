#!/bin/bash
# Export script for Transformation Composition Worksheet
# Uses Python to parse the .ggb (zip) file and extract XML data for verification
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script failed to complete"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Transformation Task Result ==="

# 1. Capture final state
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis script
# This script searches for the file, unzips it, parses XML, and outputs JSON
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
EXPECTED_DIR = "/home/ga/Documents/GeoGebra/projects"
EXPECTED_FILENAME = "transformation_demo.ggb"
EXPECTED_PATH = os.path.join(EXPECTED_DIR, EXPECTED_FILENAME)
TASK_START_FILE = "/tmp/task_start_time"

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "points": [],
    "commands": [],
    "text_elements": [],
    "polygons": [],
    "lines": [],
    "has_reflect_command": False,
    "has_rotate_command": False,
    "timestamp": int(time.time())
}

# 1. Get task start time
try:
    with open(TASK_START_FILE, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 2. Find the file (priority: expected path -> any recent .ggb)
found_file = None
if os.path.exists(EXPECTED_PATH):
    found_file = EXPECTED_PATH
else:
    # Search for any .ggb file modified after task start
    search_pattern = os.path.join(os.path.expanduser("~"), "**", "*.ggb")
    candidates = glob.glob(search_pattern, recursive=True)
    # Sort by modification time (newest first)
    candidates.sort(key=os.path.getmtime, reverse=True)
    
    for c in candidates:
        if task_start > 0 and os.path.getmtime(c) >= task_start:
            found_file = c
            break

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    result["file_size"] = os.path.getsize(found_file)
    mtime = int(os.path.getmtime(found_file))
    result["file_modified"] = mtime
    result["file_created_during_task"] = (mtime >= task_start)

    # 3. Parse GeoGebra XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Parse XML tree
                root = ET.fromstring(xml_content)
                construction = root.find('.//construction')
                if construction is None:
                    construction = root

                # Extract Points
                for elem in construction.findall(".//element[@type='point']"):
                    label = elem.get('label', '?')
                    coords = elem.find('./coords')
                    if coords is not None:
                        try:
                            x = float(coords.get('x', 0))
                            y = float(coords.get('y', 0))
                            z = float(coords.get('z', 1))
                            # Handle homogeneous coordinates
                            if abs(z) > 1e-6:
                                result["points"].append({"label": label, "x": x/z, "y": y/z})
                            else:
                                result["points"].append({"label": label, "x": x, "y": y})
                        except:
                            pass

                # Extract Commands
                for cmd in construction.findall(".//command"):
                    name = cmd.get('name', '')
                    input_elem = cmd.find('./input')
                    output_elem = cmd.find('./output')
                    
                    cmd_data = {"name": name}
                    if input_elem is not None:
                        cmd_data["input"] = {k:v for k,v in input_elem.attrib.items()}
                    if output_elem is not None:
                        cmd_data["output"] = {k:v for k,v in output_elem.attrib.items()}
                    
                    result["commands"].append(cmd_data)
                    
                    # Check for specific transformation commands
                    if "Reflect" in name or "Mirror" in name:
                        result["has_reflect_command"] = True
                    if "Rotate" in name:
                        result["has_rotate_command"] = True

                # Extract Text
                for elem in construction.findall(".//element[@type='text']"):
                    result["text_elements"].append(elem.get('label', 'text'))

                # Extract Polygons
                for elem in construction.findall(".//element[@type='polygon']"):
                    result["polygons"].append(elem.get('label', 'poly'))

                # Extract Lines (for y=x check)
                for elem in construction.findall(".//element[@type='line']"):
                    label = elem.get('label', '?')
                    # Try to get equation coefficients if available
                    coords = elem.find('./coords')
                    line_data = {"label": label}
                    if coords is not None:
                        # ax + by + c = 0
                        line_data["x"] = float(coords.get('x', 0))
                        line_data["y"] = float(coords.get('y', 0))
                        line_data["z"] = float(coords.get('z', 0))
                    result["lines"].append(line_data)

    except Exception as e:
        result["xml_error"] = str(e)

# 4. Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete. JSON saved.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="