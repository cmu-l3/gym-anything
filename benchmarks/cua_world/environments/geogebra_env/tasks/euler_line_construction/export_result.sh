#!/bin/bash
# Export script for Euler Line Construction
# Extracts GeoGebra XML and analyzes geometric content
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "{ \"error\": \"Export script failed\", \"file_found\": false }" > /tmp/task_result.json
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Euler Line Result ==="

# 1. Capture final state
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis script
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import math
import glob
from xml.etree import ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/euler_line.ggb"
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
    "points": [],
    "lines": [],
    "commands": [],
    "texts": [],
    "construction_stats": {
        "num_points": 0,
        "num_lines": 0,
        "num_circles": 0
    }
}

# Find file (prioritize expected path, fallback to recent)
target_file = None
if os.path.exists(EXPECTED_FILE):
    target_file = EXPECTED_FILE
else:
    # Check for any recently saved .ggb
    files = sorted(glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True), key=os.path.getmtime, reverse=True)
    for f in files:
        if os.path.getmtime(f) >= TASK_START_TIME:
            target_file = f
            break

if target_file:
    result["file_found"] = True
    result["file_path"] = target_file
    mtime = int(os.path.getmtime(target_file))
    result["file_created_during_task"] = mtime >= TASK_START_TIME
    
    try:
        with zipfile.ZipFile(target_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
                
                # Parse XML
                root = ET.fromstring(xml_content)
                construction = root.find('construction')
                
                # Extract Commands
                for cmd in construction.findall('command'):
                    result["commands"].append(cmd.get('name'))
                
                # Extract Elements
                for elem in construction.findall('element'):
                    etype = elem.get('type')
                    label = elem.get('label')
                    
                    if etype == 'point':
                        coords = elem.find('coords')
                        if coords is not None:
                            x = float(coords.get('x', 0))
                            y = float(coords.get('y', 0))
                            z = float(coords.get('z', 1))
                            
                            # Handle homogeneous coordinates
                            if abs(z) > 1e-6:
                                final_x = x / z
                                final_y = y / z
                            else:
                                final_x = x # Point at infinity
                                final_y = y
                                
                            result["points"].append({
                                "label": label,
                                "x": final_x,
                                "y": final_y
                            })
                            result["construction_stats"]["num_points"] += 1
                            
                    elif etype == 'line':
                        # Get line equation ax + by + c = 0
                        coords = elem.find('coords')
                        if coords is not None:
                            # In GeoGebra XML for lines: x, y, z usually map to coefficients
                            # But exact mapping depends on internal representation.
                            # We'll just count them for now, specific line checking is hard without algebraic form
                            pass
                        result["lines"].append({"label": label})
                        result["construction_stats"]["num_lines"] += 1
                        
                    elif etype == 'text':
                        result["texts"].append(label)
                        
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"