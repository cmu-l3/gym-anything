#!/bin/bash
# Export script for Suspension Damping Simulator task
# Analyzes the GeoGebra file and exports results to JSON

set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "sliders_found": [],
    "slider_values": {},
    "functions_found": [],
    "has_oscillator": false,
    "has_envelopes": false,
    "has_dynamic_text": false,
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

echo "=== Exporting Suspension Damping Simulator Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Python script to analyze the GGB file (which is a zip containing XML)
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import glob
import math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/suspension.ggb"
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
    "sliders_found": [],
    "slider_values": {},
    "functions_found": [],
    "has_oscillator": False,
    "has_envelopes": False,
    "has_dynamic_text": False,
    "xml_content_snippet": ""
}

# Find the file (expected path or recent scan)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for any recently created ggb file in projects
    candidates = sorted(
        glob.glob("/home/ga/Documents/GeoGebra/projects/*.ggb"),
        key=os.path.getmtime, reverse=True
    )
    if candidates:
        found_file = candidates[0]

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    mtime = os.path.getmtime(found_file)
    result["file_created_during_task"] = (mtime >= TASK_START_TIME)

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                result["xml_content_snippet"] = xml_content[:500] # Debug snippet

                # 1. Check for Sliders (numeric elements)
                # Regex to find numeric elements and their values
                # <element type="numeric" label="m"> ... <value val="40"/>
                
                sliders = ['m', 'k', 'c']
                for s in sliders:
                    # Look for definition
                    pattern_def = r'<element type="numeric" label="' + s + r'">'
                    if re.search(pattern_def, xml_content):
                        result["sliders_found"].append(s)
                        
                        # Look for value associated with this slider
                        # We extract the block for this element to be safe
                        block_match = re.search(pattern_def + r'(.*?)</element>', xml_content, re.DOTALL)
                        if block_match:
                            block = block_match.group(1)
                            val_match = re.search(r'<value val="([0-9\.]+)"/>', block)
                            if val_match:
                                try:
                                    result["slider_values"][s] = float(val_match.group(1))
                                except:
                                    pass

                # 2. Check for Functions
                # <element type="function" ...> ... <expression label="..." exp="..."/>
                # OR <expression label="y" exp="0.1 exp(...) ..."/>
                
                # Check for oscillator (must have exp and cos)
                # Look for expression containing exp and cos
                oscillator_pattern = r'exp\(.*cos\(' 
                if re.search(oscillator_pattern, xml_content, re.IGNORECASE) or \
                   (re.search(r'exp\(', xml_content) and re.search(r'cos\(', xml_content)):
                    result["has_oscillator"] = True
                    result["functions_found"].append("oscillator")

                # Check for envelopes (must have exp but NOT cos)
                # This is tricky via regex on the whole file, but we can look for function definitions
                # that have exp but not cos.
                func_blocks = re.findall(r'<element type="function".*?</element>', xml_content, re.DOTALL)
                envelope_count = 0
                for block in func_blocks:
                    if 'exp(' in block and 'cos(' not in block:
                        envelope_count += 1
                
                if envelope_count >= 1:
                    result["has_envelopes"] = True
                    result["functions_found"].append("envelopes")

                # 3. Check for Dynamic Text
                # Text usually contains "damping ratio" or formula references
                # <element type="text" ...>
                if re.search(r'<element type="text"', xml_content) and \
                   (re.search(r'ratio', xml_content, re.IGNORECASE) or re.search(r'\\zeta', xml_content)):
                    result["has_dynamic_text"] = True

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json