#!/bin/bash
# Export script for Sunflower Phyllotaxis Model task
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_slider": false,
    "has_sequence": false,
    "list_size": 0,
    "is_dynamic": false,
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

echo "=== Exporting Sunflower Model Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python to analyze the .ggb file (Zip archive containing XML)
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/sunflower_model.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "has_slider": False,
    "slider_label": "",
    "has_sequence": False,
    "list_size": 0,
    "is_dynamic": False, # Checks if list depends on slider
    "xml_extract": ""
}

# 1. Find the file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Search for recent GGB files
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
    mtime = os.path.getmtime(found_file)
    result["file_created_during_task"] = int(mtime) >= TASK_START_TIME
    
    # 2. Analyze XML content
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Parse XML
                root = ET.fromstring(xml_content)
                
                # A. Find Slider (Numeric element with animation settings or slider range)
                sliders = []
                for elem in root.findall(".//element[@type='numeric']"):
                    label = elem.get('label')
                    # Check if it has slider properties
                    if elem.find("./slider") is not None:
                        sliders.append(label)
                        result["has_slider"] = True
                        # If label implies angle, prefer it
                        if 'angle' in label.lower() or 'alpha' in label.lower() or 'a' == label:
                            result["slider_label"] = label
                
                if not result["slider_label"] and sliders:
                    result["slider_label"] = sliders[0]
                
                # B. Find Sequence Command
                # GeoGebra stores commands like <command name="Sequence"><input .../><output .../></command>
                # The output is typically a list.
                sequences = []
                for cmd in root.findall(".//command[@name='Sequence']"):
                    sequences.append(cmd)
                    result["has_sequence"] = True
                    
                    # Check dependency: does input reference the slider?
                    inp = cmd.find("./input")
                    if inp is not None:
                        # Attributes like a0, a1, etc. hold the arguments
                        args = [inp.get(k) for k in inp.attrib.keys()]
                        full_args = " ".join([str(a) for a in args if a])
                        
                        if result["slider_label"] and result["slider_label"] in full_args:
                            result["is_dynamic"] = True
                        
                        # Fallback dependency check: if any slider label is in args
                        if not result["is_dynamic"]:
                            for s in sliders:
                                if s in full_args:
                                    result["is_dynamic"] = True
                                    break

                # C. Check List Size
                # Lists are elements of type 'list'. We need the one produced by Sequence.
                # Often the sequence command defines the list content.
                # However, 'Sequence' generates the list object. We can check the output label.
                # Alternatively, we can count points if they are instantiated objects (Sequence usually creates one list object, not N point objects in XML)
                # But we can verify the 'to' parameter in Sequence command to guess size.
                
                # Let's try to parse the 'to' argument of Sequence(expression, variable, from, to)
                # It's usually the 4th argument.
                max_sequence_len = 0
                for cmd in sequences:
                    inp = cmd.find("./input")
                    if inp is not None:
                        # GeoGebra XML args are often a0, a1, a2, a3
                        # Sequence( <Expression>, <Variable>, <Start Value>, <End Value> )
                        end_val_attr = inp.get('a3') # 'to' value
                        if end_val_attr:
                            try:
                                # It might be a number or a variable name
                                if end_val_attr.isdigit():
                                    val = int(end_val_attr)
                                    if val > max_sequence_len:
                                        max_sequence_len = val
                                else:
                                    # If it's a variable, try to find its value. 
                                    # For simplicity, assume if variable is used it's likely large enough or check if user defined n=500
                                    # This is tricky. Let's look for element with that label.
                                    pass
                            except:
                                pass
                
                if max_sequence_len > 0:
                    result["list_size"] = max_sequence_len
                else:
                    # Fallback: Check if there's a list element with many items? 
                    # GeoGebra XML doesn't always expand the list in the XML.
                    # Heuristic: If Sequence command exists and is dynamic, we assume the agent likely followed instructions for N=500.
                    # We can check command text in XML for "500" or larger numbers
                    if "500" in xml_content or "1000" in xml_content:
                         # Weak check, but better than 0
                         if result["list_size"] == 0: result["list_size"] = 500

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="