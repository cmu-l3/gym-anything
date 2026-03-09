#!/bin/bash
# Export script for Lissajous Figure Explorer task
set -o pipefail

# Fail-safe JSON creation
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_curve_command": false,
    "slider_count": 0,
    "has_text": false,
    "has_sin": false,
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

echo "=== Exporting Lissajous Task Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python analysis script inside the container
# This extracts the XML from the .ggb (ZIP) file and analyzes the construction
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/lissajous_explorer.ggb"
TASK_START_TIME = 0

try:
    with open("/tmp/task_start_time", "r") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "has_curve_command": False,
    "slider_count": 0,
    "has_text": False,
    "has_sin": False,
    "curve_uses_variables": False,
    "xml_commands": [],
    "error": None
}

# Find the file (check specific path, then loose search)
found_path = None
if os.path.exists(EXPECTED_FILE):
    found_path = EXPECTED_FILE
else:
    # Look for any recently modified .ggb file
    import glob
    files = glob.glob("/home/ga/Documents/GeoGebra/projects/*.ggb")
    files.extend(glob.glob("/home/ga/Documents/GeoGebra/*.ggb"))
    # Sort by modification time, newest first
    files.sort(key=os.path.getmtime, reverse=True)
    if files:
        found_path = files[0]

if found_path:
    result["file_found"] = True
    result["file_size"] = os.path.getsize(found_path)
    mtime = int(os.path.getmtime(found_path))
    result["file_modified"] = mtime
    result["file_created_during_task"] = (mtime >= TASK_START_TIME)
    
    try:
        # GeoGebra .ggb files are ZIP archives containing geogebra.xml
        with zipfile.ZipFile(found_path, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # 1. Check for Curve command
                # Look for <command name="Curve"> or <element type="curveCartesian">
                result["has_curve_command"] = bool(re.search(r'<command name="Curve"', xml_content, re.IGNORECASE))
                if not result["has_curve_command"]:
                    # Fallback check for the element type produced by Curve
                    result["has_curve_command"] = bool(re.search(r'<element type="curveCartesian"', xml_content, re.IGNORECASE))
                
                # 2. Count Sliders
                # Look for <command name="Slider"> or elements with slider tags
                slider_cmds = len(re.findall(r'<command name="Slider"', xml_content, re.IGNORECASE))
                # Also check for numeric elements that are sliders (GeoGebra XML format varies)
                # This regex looks for numeric elements that have a slider range defined
                slider_elements = len(re.findall(r'<element type="numeric"[^>]*>.*?<slider', xml_content, re.IGNORECASE | re.DOTALL))
                result["slider_count"] = max(slider_cmds, slider_elements)
                
                # 3. Check for Text
                result["has_text"] = bool(re.search(r'<element type="text"', xml_content, re.IGNORECASE))
                
                # 4. Check for Sin function usage
                # Check if "sin" appears in the input of expressions
                result["has_sin"] = bool(re.search(r'\bsin\(', xml_content, re.IGNORECASE))
                
                # 5. Check if Curve uses variables (heuristic)
                # We extract the inputs to the Curve command and look for variable names
                curve_inputs = re.findall(r'<command name="Curve">.*?<input ([^>]+)/>', xml_content, re.IGNORECASE | re.DOTALL)
                if curve_inputs:
                    # If the input string contains letters that aren't sin/cos/pi/t, likely variables
                    input_str = curve_inputs[0]
                    # This is a loose check; real verification happens if it works
                    if re.search(r'[a-qs-z]', input_str, re.IGNORECASE): # letters excluding r, t roughly
                        result["curve_uses_variables"] = True
                
                # Store all commands found for debugging
                cmds = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(cmds))
                
    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json