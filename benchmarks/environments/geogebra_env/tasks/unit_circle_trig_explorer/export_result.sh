#!/bin/bash
# Export script for Unit Circle Trig Explorer task
set -o pipefail

# Trap cleanup
trap 'rm -rf /tmp/ggb_extract' EXIT

# Ensure fallback result exists
if [ ! -f "/tmp/task_result.json" ]; then
    echo '{"error": "Export did not complete"}' > /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null || true
fi

# Helper functions
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Unit Circle Trig Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Find the output file
PROJECT_DIR="/home/ga/Documents/GeoGebra/projects"
EXPECTED_FILE="$PROJECT_DIR/unit_circle_trig.ggb"
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Logic to find the most likely file (expected name, or most recent .ggb)
FOUND_FILE=""
if [ -f "$EXPECTED_FILE" ]; then
    FOUND_FILE="$EXPECTED_FILE"
else
    # Look for any recent .ggb file
    FOUND_FILE=$(find "$PROJECT_DIR" -name "*.ggb" -newermt "@$TASK_START_TIME" 2>/dev/null | head -n 1)
fi

# 3. Analyze the GGB file using Python
# We use Python here to unzip the GGB and parse the XML, which is safer than bash
python3 << PYEOF
import os
import sys
import zipfile
import json
import time
import re
import xml.etree.ElementTree as ET

result = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "has_unit_circle": False,
    "has_angle_slider": False,
    "has_sine_function": False,
    "has_circle_point": False,
    "has_curve_point": False,
    "has_text": False,
    "elements": []
}

filepath = "$FOUND_FILE"
start_time = int("$TASK_START_TIME")

if filepath and os.path.exists(filepath):
    result["file_found"] = True
    result["file_path"] = filepath
    mtime = int(os.path.getmtime(filepath))
    if mtime >= start_time:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                root = ET.fromstring(xml_content)
                
                # Helper to find elements
                construction = root.find('construction')
                if construction is not None:
                    # 1. Check for Unit Circle
                    # GeoGebra stores circles as <element type="conic"> ... <eigenvectors ... val="1"/> 
                    # OR defined by command Circle((0,0), 1)
                    # We look for equation x^2 + y^2 = 1 or explicit command
                    
                    for elem in construction.findall('element'):
                        etype = elem.get('type')
                        label = elem.get('label', '')
                        result["elements"].append({"type": etype, "label": label})
                        
                        # Check Text
                        if etype == 'text':
                            result["has_text"] = True

                        # Check Slider (numeric)
                        if etype == 'numeric':
                            # Check if it is a slider
                            slider = elem.find('slider')
                            if slider is not None:
                                max_val = float(slider.get('max', 0))
                                # Expecting 2pi (approx 6.28) or 360
                                if max_val >= 6.0: 
                                    result["has_angle_slider"] = True
                        
                        # Check Function
                        if etype == 'function':
                            # Simple check for sine in definition
                            # Often stored in <expression label="f" exp="sin(x)"/>
                            # or inside the element definition
                            pass

                    # Check commands for structure (more reliable for dependencies)
                    for cmd in construction.findall('command'):
                        name = cmd.get('name')
                        input_args = cmd.find('input')
                        output_args = cmd.find('output')
                        
                        # Check Circle command
                        if name == 'Circle':
                            # Check radius arguments if present
                            result["has_unit_circle"] = True # Simplified check
                            
                    # Scan raw XML for specific definitions
                    
                    # Check for Sine Function definition
                    # Look for exp="sin(x)" or val="sin(x)"
                    if re.search(r'sin\(\s*x\s*\)', xml_content):
                        result["has_sine_function"] = True
                        
                    # Check for Unit Circle (x^2 + y^2 = 1)
                    # GeoGebra often represents unit circle conics with specific matrix coefficients
                    # Or check for "Circle" command with radius 1
                    if re.search(r'cmd="Circle".*a1="1"', xml_content) or \
                       re.search(r'x\^2\s*\+\s*y\^2\s*=\s*1', xml_content):
                        result["has_unit_circle"] = True

                    # Check for Point on Circle: (cos(a), sin(a))
                    # We look for an expression containing cos and sin of the same variable
                    # This is a heuristic check
                    if re.search(r'cos\([a-zA-Z]\).*sin\([a-zA-Z]\)', xml_content):
                        result["has_circle_point"] = True
                        
                    # Check for Point on Curve: (a, sin(a))
                    # Look for coordinate pair where x is var and y is sin(var)
                    # Matches pattern like (a, sin(a))
                    if re.search(r'\(\s*([a-zA-Z])\s*,\s*sin\(\s*\1\s*\)\s*\)', xml_content):
                        result["has_curve_point"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="