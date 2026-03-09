#!/bin/bash
# Export script for Riemann Sum Explorer task
# Extracts data from the saved .ggb file (which is a ZIP) for verification

set -o pipefail

# Trap to ensure we always output a result file
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

echo "=== Exporting Riemann Sum Result ==="

# 1. Take final screenshot
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
    take_screenshot /tmp/task_end_screenshot.png
else
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true
fi

# 2. Python script to analyze the .ggb file
# We use Python here because .ggb is a ZIP file containing XML, which is hard to parse in bash
python3 << 'PYEOF'
import os
import sys
import zipfile
import json
import time
import re
import xml.etree.ElementTree as ET

# Configuration
EXPECTED_PATH = "/home/ga/Documents/GeoGebra/projects/riemann_sums.ggb"
TASK_START_FILE = "/tmp/task_start_time"

result = {
    "file_found": False,
    "file_created_during_task": False,
    "has_sin_function": False,
    "has_slider": False,
    "has_upper_sum": False,
    "has_lower_sum": False,
    "has_integral": False,
    "has_text": False,
    "slider_details": {},
    "commands_found": []
}

try:
    # 1. Check file existence and timestamp
    if os.path.exists(EXPECTED_PATH):
        result["file_found"] = True
        mtime = os.path.getmtime(EXPECTED_PATH)
        
        task_start = 0
        if os.path.exists(TASK_START_FILE):
            with open(TASK_START_FILE, 'r') as f:
                task_start = int(f.read().strip())
        
        # Check if file was modified after task started
        if mtime >= task_start:
            result["file_created_during_task"] = True
        
        # 2. Extract and parse geogebra.xml
        try:
            with zipfile.ZipFile(EXPECTED_PATH, 'r') as z:
                if 'geogebra.xml' in z.namelist():
                    xml_content = z.read('geogebra.xml').decode('utf-8')
                    
                    # Parse XML
                    try:
                        root = ET.fromstring(xml_content)
                    except ET.ParseError:
                        # Fallback to regex if XML is malformed
                        root = None
                    
                    # Analysis logic
                    
                    # A. Check for Sine function
                    # Look for: <element type="function"> ... <expression label="f" exp="sin(x)"/> ...
                    # Or regex scan for sin(x) definition
                    if root is not None:
                        for elem in root.findall(".//element[@type='function']"):
                            # Check coords/expression
                            # Often stored in 'expression' attribute of 'command' or 'element'
                            pass # simplified logic below using regex on full content is often more robust for specific strings
                    
                    # Robust Regex Checks on XML content
                    # Function sin(x)
                    if re.search(r'exp=".*sin\(x\).*?"', xml_content, re.IGNORECASE) or \
                       re.search(r'<element type="function".*sin', xml_content, re.IGNORECASE):
                        result["has_sin_function"] = True
                        
                    # B. Check for Slider
                    # <element type="numeric" ...> <slider min="..." max="..." .../>
                    # We look for an element with type numeric that HAS a slider child
                    if root is not None:
                        for elem in root.findall(".//element[@type='numeric']"):
                            if elem.find("slider") is not None:
                                result["has_slider"] = True
                                slider = elem.find("slider")
                                result["slider_details"] = {
                                    "min": slider.get("min"),
                                    "max": slider.get("max"),
                                    "label": elem.get("label")
                                }
                                break
                    
                    # C. Check for Commands (UpperSum, LowerSum, Integral)
                    # <command name="UpperSum">
                    commands = re.findall(r'<command name="([^"]+)"', xml_content)
                    result["commands_found"] = commands
                    
                    if "UpperSum" in commands or "RectangleSum" in commands:
                        result["has_upper_sum"] = True
                    
                    if "LowerSum" in commands or "RectangleSum" in commands:
                        result["has_lower_sum"] = True
                        
                    if "Integral" in commands:
                        result["has_integral"] = True
                        
                    # D. Check for Text
                    if re.search(r'<element type="text"', xml_content):
                        result["has_text"] = True

        except Exception as e:
            result["error_parsing"] = str(e)

except Exception as e:
    result["error"] = str(e)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

print("Analysis complete. Result:")
print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="