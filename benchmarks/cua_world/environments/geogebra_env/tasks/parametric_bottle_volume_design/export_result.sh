#!/bin/bash
# Export script for Parametric Bottle Volume Design task
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": false,
    "task_start_time": 0,
    "has_surface_command": false,
    "has_integral_command": false,
    "calculated_volume": 0,
    "best_volume_candidate": 0,
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

echo "=== Exporting Bottle Design Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python script to analyze the .ggb file (zip archive containing XML)
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/bottle_design.ggb"
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
    "has_surface_command": False,
    "has_integral_command": False,
    "has_function": False,
    "calculated_volume": None,
    "best_volume_candidate": None,
    "xml_commands": []
}

# 1. Find the file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for recent .ggb files
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
    mtime = int(os.path.getmtime(found_file))
    result["file_modified"] = mtime
    result["file_created_during_task"] = mtime > TASK_START_TIME

    # 2. Parse the GGB file (ZIP)
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')

                # Check for commands
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                result["has_surface_command"] = any(cmd.lower() == 'surface' for cmd in commands)
                result["has_integral_command"] = any(cmd.lower() in ['integral', 'nintegral'] for cmd in commands)
                
                # Check for profile function (just checking if any function exists)
                # <element type="function" ...>
                result["has_function"] = bool(re.search(r'<element type="function"', xml_content))

                # 3. Find the Volume Value
                # We look for numeric elements. 
                # Strategy: Find all numeric values. If one is close to 500, that's likely the volume.
                # Also check if there's a specific variable named V or Volume.
                
                # Regex to find numeric elements and their values
                # Pattern: <element type="numeric" label="..."> ... <value val="123.45"/> ... </element>
                
                # Simple extraction of all values
                values = []
                value_matches = re.findall(r'<value val="([-0-9\.]+)"/>', xml_content)
                for v_str in value_matches:
                    try:
                        val = float(v_str)
                        values.append(val)
                    except ValueError:
                        pass
                
                # Filter values reasonably close to target to identify "best candidate"
                # This helps if the user named it something random but got the right math
                target = 500.0
                candidates = [v for v in values if 0 <= v <= 10000] # Filter out crazy values
                
                best_diff = float('inf')
                best_val = None
                
                for v in candidates:
                    diff = abs(v - target)
                    if diff < best_diff:
                        best_diff = diff
                        best_val = v
                
                result["best_volume_candidate"] = best_val

                # Try to look for specific variables related to integration
                # If we find an Integral command, look at its output label
                # <command name="Integral"> ... <output a0="V"/> ... </command>
                integral_outputs = re.findall(r'<command name="Integral">.*?<output a0="([^"]+)"/>', xml_content, re.DOTALL)
                
                for label in integral_outputs:
                    # Find the value for this label
                    # <element type="numeric" label="V"> ... <value val="..."/>
                    # We need a somewhat more complex regex or simple parsing
                    label_pattern = r'<element type="numeric" label="' + re.escape(label) + r'">.*?<value val="([-0-9\.]+)"/>'
                    val_match = re.search(label_pattern, xml_content, re.DOTALL)
                    if val_match:
                        try:
                            val = float(val_match.group(1))
                            result["calculated_volume"] = val
                            # If we found a value specifically from an Integral command, it overrides general search
                            # unless it's wildly wrong and the general search found a better 500 match (unlikely)
                        except ValueError:
                            pass

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="