#!/bin/bash
# Export script for Coaster Loop Reconstruction
set -o pipefail

# Fallback result creation
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_image": false,
    "has_curve": false,
    "has_integrals": false,
    "has_height_text": false,
    "reported_height": 0,
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

echo "=== Exporting Results ==="

# 1. Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze the GGB file using Python
# We embed the python script to handle XML parsing robustly
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import glob
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/coaster_reconstruction.ggb"
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
    "has_image": False,
    "has_curve": False,
    "has_integrals": False,
    "has_height_text": False,
    "reported_height": 0.0,
    "xml_commands": []
}

# Find file (expected or most recent)
target_file = None
if os.path.exists(EXPECTED_FILE):
    target_file = EXPECTED_FILE
else:
    # Check for any recent ggb
    files = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
    files.sort(key=os.path.getmtime, reverse=True)
    if files:
        target_file = files[0]

if target_file and os.path.exists(target_file):
    result["file_found"] = True
    result["file_path"] = target_file
    mtime = os.path.getmtime(target_file)
    if TASK_START_TIME > 0 and mtime >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # Parse GGB (it's a zip)
    try:
        with zipfile.ZipFile(target_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check for Image
                if re.search(r'<element type="image"', xml_content):
                    result["has_image"] = True
                
                # Check for Curve element
                if re.search(r'<element type="curve"', xml_content):
                    result["has_curve"] = True

                # Check for commands involving integrals/Fresnel
                # Look for Curve commands specifically
                # Pattern: command name="Curve" ... input ... cos ... t^2 ...
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))
                
                # Check for logic of clothoid (integrals of trig functions)
                # We check the entire XML for the mathematical definition usually found in expression attributes
                # Look for "integral" and "cos" or "sin" in close proximity, or "Fresnel"
                lower_xml = xml_content.lower()
                
                has_integral_keyword = "integral" in lower_xml or "nintegral" in lower_xml
                has_trig_square = ("cos" in lower_xml and "^2" in lower_xml) or ("sin" in lower_xml and "^2" in lower_xml)
                has_fresnel = "fresnel" in lower_xml
                
                if (has_integral_keyword and has_trig_square) or has_fresnel:
                    result["has_integrals"] = True
                
                # Check for Text element (height label)
                text_elements = re.findall(r'<element type="text".*?>.*?</element>', xml_content, re.DOTALL)
                if text_elements:
                    result["has_height_text"] = True
                    # Try to parse a number from text (e.g. "Height = 35m")
                    for te in text_elements:
                        # Extract the text content usually in 'label' or 'startPoint' attributes or CDATA? 
                        # In XML, the text content is often referenced or stored in <val> or separate attributes
                        # Simple regex for number + m
                        match = re.search(r'([0-9]+\.?[0-9]*)\s*m', te)
                        if match:
                            result["reported_height"] = float(match.group(1))
                            break
                        # Also check the 'label' or visual caption if stored elsewhere
                        # Simpler: just grep numbers from the whole file that might be height annotations
                        
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true