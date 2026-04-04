#!/bin/bash
# Export script for Analemmatic Sundial task
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
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

echo "=== Exporting Sundial Result ==="

take_screenshot /tmp/task_final.png

# Use Python to analyze the .ggb file (which is a zip containing XML)
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

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/sundial_chicago.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "points": [],
    "conics": [],
    "texts": [],
    "commands": [],
    "task_start": TASK_START_TIME,
    "task_end": int(time.time())
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
    mtime = os.path.getmtime(found_file)
    result["file_created_during_task"] = int(mtime) >= TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                try:
                    root = ET.fromstring(xml_content)
                    construction = root.find('.//construction')
                    
                    if construction is not None:
                        # Extract Points
                        for elem in construction.findall('element'):
                            etype = elem.get('type', '')
                            elabel = elem.get('label', '')
                            
                            if etype == 'point':
                                coords = elem.find('coords')
                                if coords is not None:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z_coord = float(coords.get('z', 1))
                                    # Handle homogeneous coordinates
                                    if abs(z_coord) > 1e-6:
                                        result["points"].append({
                                            "label": elabel,
                                            "x": x/z_coord,
                                            "y": y/z_coord
                                        })
                            
                            elif etype == 'conic':
                                # GeoGebra stores conics as matrix coefficients or specific params
                                # We'll try to extract the definition from the command or coords
                                # For ellipses, we often look at eigenvecs/eigenvals or equation
                                # Simplified: just check if it exists for now, verification logic 
                                # usually infers shape from construction points or equation string
                                eqn_node = elem.find('equation') # Sometimes present
                                result["conics"].append({
                                    "label": elabel,
                                    "type": "conic"
                                })
                                
                            elif etype == 'text':
                                # Try to get text content. GeoGebra XML structure varies for text.
                                # Often it's not directly in element text but in attributes or startVal
                                # We'll check the element attributes/properties
                                result["texts"].append(elabel) # Just recording label existence for now

                        # Extract Commands to see methods used
                        for cmd in construction.findall('command'):
                            cname = cmd.get('name', '')
                            result["commands"].append(cname)
                            
                except ET.ParseError:
                    print("XML Parse Error")
                    
    except Exception as e:
        print(f"Error analyzing GGB file: {e}")

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="