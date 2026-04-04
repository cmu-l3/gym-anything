#!/bin/bash
# Export script for Basketball Bank Shot Simulator
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
    "sliders_found": 0,
    "has_curve_command": false,
    "has_conditional": false,
    "has_physics_gravity": false,
    "has_backboard_geometry": false,
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

echo "=== Exporting Results ==="

# 1. Capture final visual state
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze the GGB file using Python
# We interpret the .ggb (zip) file to check XML content directly
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import glob

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/bank_shot.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "file_mtime": 0,
    "sliders_found": 0,
    "slider_labels": [],
    "has_curve_command": False,
    "has_conditional": False,
    "has_physics_gravity": False,
    "has_backboard_geometry": False,
    "xml_snippet": ""
}

# Find file (robust search)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for any recently created ggb files
    candidates = sorted(glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True), 
                        key=os.path.getmtime, reverse=True)
    for c in candidates:
        if TASK_START_TIME > 0 and os.path.getmtime(c) >= TASK_START_TIME:
            found_file = c
            break

if found_file:
    result["file_found"] = True
    mtime = os.path.getmtime(found_file)
    result["file_mtime"] = mtime
    result["file_created_during_task"] = (mtime >= TASK_START_TIME)
    
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml = z.read('geogebra.xml').decode('utf-8', errors='ignore')
                
                # Check 1: Sliders (numeric elements with animation tags or simply numeric)
                # We look for <element type="numeric">
                sliders = re.findall(r'<element type="numeric"[^>]*>\s*<show[^>]*/>\s*<objColor[^>]*/>\s*<layer[^>]*/>\s*<labelMode[^>]*/>\s*<animation', xml, re.DOTALL)
                # Broader check for any numeric elements that might be sliders
                numeric_elements = re.findall(r'<element type="numeric"[^>]* label="([^"]+)"', xml)
                result["sliders_found"] = len(numeric_elements)
                result["slider_labels"] = numeric_elements
                
                # Check 2: Curve Command (Parametric)
                # Look for <command name="Curve"> or <command name="CurveCartesian">
                if re.search(r'<command name="Curve', xml, re.IGNORECASE):
                    result["has_curve_command"] = True
                
                # Check 3: Conditional Logic (If statements)
                # Look for <command name="If"> or usage of If( in expressions
                if re.search(r'<command name="If"', xml, re.IGNORECASE) or 'If(' in xml:
                    result["has_conditional"] = True
                    
                # Check 4: Physics Constants (9.8 for gravity)
                # Look for 9.8 in expressions or values
                if '9.8' in xml:
                    result["has_physics_gravity"] = True
                    
                # Check 5: Backboard Geometry (x = 4.6)
                # Look for line definitions or fixed points at 4.6
                if '4.6' in xml or 'x = 4.6' in xml:
                    result["has_backboard_geometry"] = True
                    
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"