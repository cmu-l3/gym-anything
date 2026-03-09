#!/bin/bash
# Export script for Ship Stability Metacenter Analysis
set -o pipefail

# Ensure we capture a result even if something fails
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script failed to run or crashed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Ship Stability Result ==="

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Analyze the GeoGebra file using Python
# We embed the python script here to avoid dependency issues
python3 << 'PYEOF'
import os
import sys
import zipfile
import json
import time
import re
import xml.etree.ElementTree as ET

EXPECTED_PATH = "/home/ga/Documents/GeoGebra/projects/barge_stability.ggb"
TASK_START_FILE = "/tmp/task_start_time"

result = {
    "file_found": False,
    "file_created_during_task": False,
    "file_size": 0,
    "xml_valid": False,
    "commands_found": [],
    "objects": {
        "polygons": 0,
        "segments": 0,
        "points": 0,
        "texts": []
    },
    "gm_value_found": False,
    "gm_value": None,
    "rotation_found": False,
    "centroid_found": False,
    "intersect_found": False,
    "unstable_text_found": False
}

# Check start time
task_start = 0
if os.path.exists(TASK_START_FILE):
    with open(TASK_START_FILE, 'r') as f:
        try:
            task_start = int(f.read().strip())
        except:
            pass

# Check file existence
if os.path.exists(EXPECTED_PATH):
    result["file_found"] = True
    result["file_size"] = os.path.getsize(EXPECTED_PATH)
    mtime = os.path.getmtime(EXPECTED_PATH)
    
    if task_start > 0 and mtime >= task_start:
        result["file_created_during_task"] = True
    
    # Analyze GGB content (it's a zip)
    try:
        with zipfile.ZipFile(EXPECTED_PATH, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
                result["xml_valid"] = True
                
                # Regex analysis for speed/robustness
                
                # 1. Check for specific commands
                result["commands_found"] = re.findall(r'<command name="([^"]+)"', xml_content)
                
                if "Rotate" in result["commands_found"]:
                    result["rotation_found"] = True
                
                if "Centroid" in result["commands_found"]:
                    result["centroid_found"] = True
                    
                if "Intersect" in result["commands_found"]:
                    result["intersect_found"] = True

                # 2. Count objects
                result["objects"]["polygons"] = len(re.findall(r'<element type="polygon"', xml_content))
                result["objects"]["points"] = len(re.findall(r'<element type="point"', xml_content))
                result["objects"]["segments"] = len(re.findall(r'<element type="segment"', xml_content))
                
                # 3. Check for text annotations
                # Extract text content from <element type="text"> ... <startVal val="..."/>
                # XML parsing is safer for nested attributes
                try:
                    root = ET.fromstring(xml_content)
                    construction = root.find("./construction")
                    if construction:
                        for elem in construction.findall("element"):
                            if elem.get("type") == "text":
                                # Text value might be in different places depending on version
                                # Often in 'val' attribute of element or child
                                # Let's search raw regex for "Unstable" to be safe
                                pass
                except:
                    pass
                
                # Crude text check
                if re.search(r'Unstable', xml_content, re.IGNORECASE):
                    result["unstable_text_found"] = True

                # 4. Check for GM value (approx 0.22)
                # Look for numeric values in value attributes
                # Pattern: value="0.22..."
                numeric_values = re.findall(r'value="([0-9]+\.[0-9]+)"', xml_content)
                for val_str in numeric_values:
                    try:
                        val = float(val_str)
                        if 0.15 <= val <= 0.30: # Wide tolerance around 0.22
                            result["gm_value_found"] = True
                            result["gm_value"] = val
                    except:
                        pass
                        
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json