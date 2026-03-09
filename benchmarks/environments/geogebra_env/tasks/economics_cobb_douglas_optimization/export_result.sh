#!/bin/bash
# Export script for Economics Optimization task
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
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

echo "=== Exporting Economics Optimization Result ==="

# 1. Capture final screenshot (crucial for visual verification of colors)
take_screenshot /tmp/task_end_screenshot.png

# 2. Python script to analyze the .ggb file structure
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/utility_max.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "sliders_found": [],
    "budget_line_found": False,
    "budget_line_color": None,
    "optimal_point_found": False,
    "optimal_point_dynamic": False,
    "indifference_curve_found": False,
    "indifference_curve_color": None,
    "xml_parsed_successfully": False
}

# Find file (robust search)
target_file = None
if os.path.exists(EXPECTED_FILE):
    target_file = EXPECTED_FILE
else:
    # Check for recent files in directory
    import glob
    candidates = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
    candidates.sort(key=os.path.getmtime, reverse=True)
    if candidates:
        target_file = candidates[0]

if target_file and os.path.exists(target_file):
    result["file_found"] = True
    mtime = os.path.getmtime(target_file)
    if mtime >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # Parse GGB (Zip archive)
    try:
        with zipfile.ZipFile(target_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
                result["xml_parsed_successfully"] = True
                
                # Use ElementTree for structured parsing
                root = ET.fromstring(xml_content)
                
                # 1. Check for Sliders (numeric elements with animation allowed usually)
                # Looking for elements like <element type="numeric" label="I">
                for elem in root.findall(".//element[@type='numeric']"):
                    label = elem.get('label', '')
                    # Sliders usually have a value and animation tag, or just match our expected names
                    if label in ['I', 'Px', 'Py', 'i', 'px', 'py', 'PX', 'PY']:
                        result["sliders_found"].append(label)
                
                # 2. Check for Budget Line (type="line")
                for elem in root.findall(".//element[@type='line']"):
                    label = elem.get('label', '')
                    # Check color
                    color_tag = elem.find("./objColor")
                    if color_tag is not None:
                        r = int(color_tag.get('r', 0))
                        g = int(color_tag.get('g', 0))
                        b = int(color_tag.get('b', 0))
                        # Red-ish: High R, Low G/B
                        if r > 150 and g < 100 and b < 100:
                            result["budget_line_color"] = "red"
                            result["budget_line_found"] = True
                    else:
                        # If found but not colored, mark found
                        result["budget_line_found"] = True

                # 3. Check for Optimal Point (type="point")
                for elem in root.findall(".//element[@type='point']"):
                    label = elem.get('label', '')
                    # Check dependency in expression
                    # The logic is in the <expression> tag, usually linked by label
                    # But often inside the <command> or <expression> tag at root level matching label
                    # In geogebra XML, often: <expression label="A" exp="(I / (2 Px), I / (2 Py))" />
                    
                    # We need to find the expression associated with this point to check dynamic nature
                    # Search all expressions
                    expr_tag = root.find(f".//expression[@label='{label}']")
                    if expr_tag is not None:
                        exp_str = expr_tag.get('exp', '')
                        # Check if it depends on sliders (contains variable names)
                        if any(s in exp_str for s in result["sliders_found"]):
                            result["optimal_point_dynamic"] = True
                            result["optimal_point_found"] = True
                    
                    # Alternatively, if it was created via command
                    cmd_tag = root.find(f".//command/output[@a0='{label}']/..")
                    if cmd_tag is not None:
                        # It's a command result (like Intersect or similar)
                        result["optimal_point_found"] = True
                        result["optimal_point_dynamic"] = True # Commands usually imply dynamic

                # 4. Check for Indifference Curve (implicitpoly, conic, function)
                # Looking for x*y = k or y = k/x
                for tag_type in ['implicitpoly', 'conic', 'function']:
                    for elem in root.findall(f".//element[@type='{tag_type}']"):
                        # Check color
                        color_tag = elem.find("./objColor")
                        color = "unknown"
                        if color_tag is not None:
                            r = int(color_tag.get('r', 0))
                            g = int(color_tag.get('g', 0))
                            b = int(color_tag.get('b', 0))
                            # Blue-ish: Low R, Low G, High B
                            if b > 150 and r < 100 and g < 100:
                                color = "blue"
                        
                        result["indifference_curve_found"] = True
                        if color == "blue":
                            result["indifference_curve_color"] = "blue"

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json