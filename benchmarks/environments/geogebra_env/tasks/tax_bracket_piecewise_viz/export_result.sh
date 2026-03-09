#!/bin/bash
# Export script for Tax Bracket Visualization task
set -o pipefail

# Ensure fallback result on any failure
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

echo "=== Exporting Tax Bracket Visualization Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python script to parse the .ggb file (zip archive) and extract logic
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import glob
import shutil

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/tax_brackets.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "file_size": 0,
    "num_if_commands": 0,
    "num_sliders": 0,
    "num_texts": 0,
    "bracket_values_found": [],
    "rates_found": [],
    "axis_x_max": 0,
    "axis_y_max": 0,
    "function_definitions": []
}

# 1. Find the file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for recent .ggb files
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
    mtime = int(os.path.getmtime(found_file))
    result["file_created_during_task"] = mtime >= TASK_START_TIME

    # 2. Extract and Parse geogebra.xml
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Count If commands (piecewise logic)
                result["num_if_commands"] = len(re.findall(r'<command name="If"', xml_content, re.IGNORECASE))
                
                # Count Sliders
                # Sliders are numeric elements with isSlider="true" or just numeric with range
                # Simple regex check for element type="numeric"
                result["num_sliders"] = len(re.findall(r'<element type="numeric"', xml_content))
                
                # Count Text elements
                result["num_texts"] = len(re.findall(r'<element type="text"', xml_content))
                
                # Extract Axis Settings (EuclidianView)
                # Looking for <coordSystem xZero="..." yZero="..." scale="..."/> 
                # or <evSettings xMin="..." xMax="..." .../>
                # Since XML parsing with regex is brittle, we look for numbers near xMax
                x_max_match = re.search(r'xMax="([0-9\.]+)"', xml_content)
                if x_max_match:
                    result["axis_x_max"] = float(x_max_match.group(1))
                y_max_match = re.search(r'yMax="([0-9\.]+)"', xml_content)
                if y_max_match:
                    result["axis_y_max"] = float(y_max_match.group(1))

                # Extract Function Definitions to check for brackets and rates
                # GeoGebra stores definitions in attributes like `exp` or `<expression .../>`
                # We'll just scan the whole XML content for specific numbers
                
                # Check for bracket boundaries (11600, 47150, 100525, 191950)
                # Allow for comma formatting (11,600) or plain
                brackets_to_check = [11600, 47150, 100525, 191950, 243725, 609350]
                for b in brackets_to_check:
                    # Regex for number with optional comma
                    pat = str(b)
                    if re.search(pat, xml_content):
                        result["bracket_values_found"].append(b)
                
                # Check for tax rates (0.1, 0.12, 0.22 etc)
                # Note: 10% might be stored as 0.1 or 10/100
                rates_to_check = [0.1, 0.12, 0.22, 0.24, 0.32, 0.35]
                for r in rates_to_check:
                    # Check for 0.12 or .12
                    pat = str(r).replace('0.', '[0]*\.')
                    if re.search(pat, xml_content):
                        result["rates_found"].append(r)
                        
    except Exception as e:
        result["error"] = f"Failed to parse GGB file: {str(e)}"

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result:"
cat /tmp/task_result.json