#!/bin/bash
# Export script for Fourier Square Wave Approximation task
# Extracts XML from the .ggb file and analyzes it for the Fourier construction elements
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_slider": false,
    "has_sum_command": false,
    "has_square_wave": false,
    "has_text": false,
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

echo "=== Exporting Fourier Task Result ==="

# 1. Capture final state evidence
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze the result file using embedded Python
# We use Python here because parsing XML with regex in bash is fragile,
# and we need to handle the .ggb (zip) format.
python3 << 'PYEOF'
import os
import sys
import zipfile
import json
import re
import time
import glob
import xml.etree.ElementTree as ET

EXPECTED_PATH = "/home/ga/Documents/GeoGebra/projects/fourier_square_wave.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_created_during_task": False,
    "has_slider": False,
    "slider_details": {},
    "has_sum_command": False,
    "has_square_wave": False,
    "has_text": False,
    "xml_commands": [],
    "timestamp": int(time.time())
}

# Find the file (check expected path, then fallback to recent files)
found_file = None
if os.path.exists(EXPECTED_PATH):
    found_file = EXPECTED_PATH
else:
    # Look for any recent ggb file in the projects dir
    search_dir = "/home/ga/Documents/GeoGebra/projects"
    files = glob.glob(os.path.join(search_dir, "*.ggb"))
    files.sort(key=os.path.getmtime, reverse=True)
    if files:
        found_file = files[0]

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    result["file_size"] = os.path.getsize(found_file)
    
    # Check timestamp
    mtime = os.path.getmtime(found_file)
    if TASK_START_TIME > 0 and int(mtime) >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # Analyze contents
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Parse XML
                root = ET.fromstring(xml_content)
                
                # 1. Check for Slider
                # Sliders are usually <element type="numeric"> with <slider> child
                # Or simply commands that create numbers with sliders
                sliders = []
                for elem in root.findall(".//element[@type='numeric']"):
                    slider_node = elem.find("slider")
                    if slider_node is not None:
                        sliders.append(elem.get("label"))
                        # Check bounds if possible
                        min_val = slider_node.get("min")
                        max_val = slider_node.get("max")
                        result["slider_details"] = {"label": elem.get("label"), "min": min_val, "max": max_val}
                
                if sliders:
                    result["has_slider"] = True
                
                # 2. Check for Sum command
                # Look for <command name="Sum">
                commands = []
                for cmd in root.findall(".//command"):
                    name = cmd.get("name")
                    commands.append(name)
                    if name == "Sum":
                        result["has_sum_command"] = True
                result["xml_commands"] = list(set(commands))
                
                # 3. Check for Square Wave definition
                # Look for expressions containing "sgn(sin" or "If(sin" or "If[sin"
                # Searching raw XML content for regex patterns is often more robust for expressions
                # as they might be in attributes or child nodes
                square_patterns = [
                    r'sgn\s*\(\s*sin', 
                    r'If\s*[\(\[]\s*sin',
                    r'sign\s*\(\s*sin',
                    r'sin\s*\(\s*x\s*\)\s*>\s*0', # Conditional logic
                    r'sin\s*\(\s*x\s*\)\s*>=\s*0'
                ]
                for pat in square_patterns:
                    if re.search(pat, xml_content, re.IGNORECASE):
                        result["has_square_wave"] = True
                        break
                
                # 4. Check for Text annotation
                # <element type="text">
                text_elems = root.findall(".//element[@type='text']")
                if text_elems:
                    result["has_text"] = True

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="