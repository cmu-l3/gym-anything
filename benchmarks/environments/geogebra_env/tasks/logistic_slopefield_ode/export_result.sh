#!/bin/bash
# Export script for Logistic Slope Field task
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
    "has_slopefield": false,
    "solve_ode_count": 0,
    "slider_count": 0,
    "has_text": false,
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Logistic Slope Field Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python analysis script
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import xml.etree.ElementTree as ET

EXPECTED_PATH = "/home/ga/Documents/GeoGebra/projects/logistic_slopefield.ggb"
TASK_START_TIME = 0

try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "has_slopefield": False,
    "solve_ode_count": 0,
    "slider_count": 0,
    "has_text": False,
    "xml_commands": [],
    "error": None
}

# 1. Find the .ggb file
found_file = None
if os.path.exists(EXPECTED_PATH):
    found_file = EXPECTED_PATH
else:
    # Look for any recent .ggb file
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
    mtime = os.path.getmtime(found_file)
    result["file_modified"] = int(mtime)
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    # 2. Extract and parse geogebra.xml
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Simple Regex checks for robustness (sometimes XML parsing is tricky with namespaces)
                
                # Check for SlopeField command
                # Pattern: <command name="SlopeField">
                slope_cmds = re.findall(r'<command name="SlopeField"', xml_content, re.IGNORECASE)
                result["has_slopefield"] = len(slope_cmds) > 0
                
                # Check for SolveODE command
                # Pattern: <command name="SolveODE"> or <command name="NSolveODE">
                solve_cmds = re.findall(r'<command name="(N)?SolveODE"', xml_content, re.IGNORECASE)
                result["solve_ode_count"] = len(solve_cmds)
                
                # Extract all commands for debugging
                all_cmds = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(all_cmds))
                
                # XML Tree Parsing for elements (Sliders and Text)
                # We wrap in a dummy root if needed, but usually geogebra.xml has a root
                try:
                    root = ET.fromstring(xml_content)
                    
                    # Count Sliders: Look for <element type="numeric"> with a <slider> child
                    sliders = 0
                    texts = 0
                    
                    # GeoGebra XML structure: <construction> -> <element>
                    # Note: iter() finds elements anywhere in tree
                    for elem in root.iter('element'):
                        etype = elem.get('type', '')
                        
                        if etype == 'numeric':
                            if elem.find('slider') is not None:
                                sliders += 1
                        elif etype == 'text':
                            # Check if text is not empty
                            # Sometimes text is in 'val' attribute or text child?
                            # Usually <element type="text" label="...">
                            texts += 1
                            
                    result["slider_count"] = sliders
                    result["has_text"] = texts > 0
                    
                except Exception as e:
                    # Fallback if XML parsing fails: use regex
                    result["error_xml_parse"] = str(e)
                    result["slider_count"] = len(re.findall(r'<slider ', xml_content))
                    result["has_text"] = len(re.findall(r'<element type="text"', xml_content)) > 0
                    
    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

print("Export complete. Result:")
print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true