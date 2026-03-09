#!/bin/bash
# Export script for SIR Calibration task
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "{ \"error\": \"Export script failed\", \"file_found\": false }" > /tmp/task_result.json
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting SIR Calibration Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis script
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/sir_analysis.ggb"
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
    "has_data_points": False,
    "has_ode_command": False,
    "has_sliders": False,
    "parameter_beta": None,
    "parameter_gamma": None,
    "num_points": 0,
    "command_list": []
}

# Find the file (check expected path, then search recent)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
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
    mtime = int(os.path.getmtime(found_file))
    result["file_created_during_task"] = (mtime >= TASK_START_TIME)

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # 1. Check for Data Points (The CSV has 13 rows)
                # Look for points. Real points from data usually have fixed coords.
                points = re.findall(r'<element type="point"', xml_content)
                result["num_points"] = len(points)
                result["has_data_points"] = len(points) >= 10

                # 2. Check for ODE Command
                # SolveODE, NSolveODE, or Euler method in spreadsheet
                cmds = re.findall(r'<command name="([^"]+)"', xml_content)
                result["command_list"] = list(set(cmds))
                
                has_ode = False
                for cmd in result["command_list"]:
                    if "ODE" in cmd.upper() or "SOLVE" in cmd.upper() or "INTEGRAL" in cmd.upper():
                        has_ode = True
                result["has_ode_command"] = has_ode

                # 3. Extract Slider Values (Parameters)
                # We search for ALL numeric values and see if any pair matches our ranges.
                # This makes us robust to naming (beta vs b vs param1).
                
                # Parse XML to find numeric elements
                try:
                    root = ET.fromstring(xml_content)
                    
                    # Store all numeric values found in the file
                    numeric_values = []
                    
                    # Look in <element type="numeric">
                    for elem in root.findall(".//element[@type='numeric']"):
                        val_attr = elem.get('value')
                        label = elem.get('label', 'unknown')
                        
                        # Sometimes value is in 'val' attribute, sometimes 'value'
                        # In GeoGebra XML, it's often 'val' inside the element tag for sliders
                        # or computed dynamically.
                        # Let's look for <value val="..."/> child
                        val_child = elem.find("value")
                        if val_child is not None:
                            try:
                                val = float(val_child.get("val", 0))
                                numeric_values.append((label, val))
                            except:
                                pass
                                
                    # If empty, try regex backup for <value val="...">
                    if not numeric_values:
                        matches = re.findall(r'<value\s+val="([\d\.-]+)"', xml_content)
                        numeric_values = [("regex", float(m)) for m in matches]

                    # Identify best candidates for Beta and Gamma
                    # Target Beta ~ 1.66 (range 0-5 typically)
                    # Target Gamma ~ 0.44 (range 0-2 typically)
                    
                    best_beta = None
                    best_gamma = None
                    
                    # Heuristic: Find value closest to 1.66
                    candidates_beta = [v for l,v in numeric_values if 1.0 <= v <= 2.5]
                    if candidates_beta:
                        best_beta = min(candidates_beta, key=lambda x: abs(x - 1.66))
                        
                    # Heuristic: Find value closest to 0.44
                    candidates_gamma = [v for l,v in numeric_values if 0.2 <= v <= 0.8]
                    if candidates_gamma:
                        best_gamma = min(candidates_gamma, key=lambda x: abs(x - 0.44))
                        
                    result["parameter_beta"] = best_beta
                    result["parameter_gamma"] = best_gamma
                    result["has_sliders"] = (best_beta is not None and best_gamma is not None)
                    
                except Exception as e:
                    result["xml_parse_error"] = str(e)

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json