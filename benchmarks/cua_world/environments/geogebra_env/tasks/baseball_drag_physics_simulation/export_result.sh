#!/bin/bash
# Export script for Baseball Drag Physics task
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_ode_command": false,
    "points_found": [],
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

echo "=== Exporting Baseball Physics Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Python script to analyze the GGB file structure
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/baseball_physics.ggb"
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
    "task_end_time": int(time.time()),
    "xml_commands": [],
    "has_ode_command": False,
    "has_sequence_command": False,
    "points_on_axis": [],
    "variables_defined": []
}

# Find file
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
    result["file_size"] = os.path.getsize(found_file)
    mtime = os.path.getmtime(found_file)
    result["file_modified"] = int(mtime)
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')

                # 1. Check for commands used
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))
                
                # Check for ODE solvers or numerical methods
                ode_cmds = ["SolveODE", "NSolveODE", "SlopeField", "Integral"]
                result["has_ode_command"] = any(cmd in commands for cmd in ode_cmds)
                
                # Check for iterative/sequence methods (alternative to SolveODE)
                result["has_sequence_command"] = "Sequence" in commands or "Iteration" in commands

                # 2. Extract Points
                # We are looking for landing points on y=0 (approx)
                # Parse <element type="point">...<coords x="..." y="..." z="..."/>
                import xml.etree.ElementTree as ET
                try:
                    root = ET.fromstring(xml_content)
                    construction = root.find('.//construction')
                    if construction is not None:
                        for elem in construction.findall('element'):
                            if elem.get('type') == 'point':
                                label = elem.get('label', '')
                                coords = elem.find('coords')
                                if coords is not None:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z = float(coords.get('z', 1))
                                    
                                    if abs(z) > 1e-6:
                                        rx = x/z
                                        ry = y/z
                                        # Only care about points roughly on the ground (y approx 0)
                                        # and reasonably far from origin (x > 10)
                                        if abs(ry) < 2.0 and rx > 10:
                                            result["points_on_axis"].append({
                                                "label": label,
                                                "x": rx,
                                                "y": ry
                                            })
                            
                            # Check for numeric variables (Mass, Cd, etc)
                            elif elem.get('type') == 'numeric':
                                label = elem.get('label', '')
                                val_elem = elem.find('value')
                                if val_elem is not None:
                                    val = float(val_elem.get('val', 0))
                                    result["variables_defined"].append({"label": label, "value": val})

                except Exception as e:
                    print(f"XML Parsing error: {e}")

    except Exception as e:
        print(f"Zip read error: {e}")

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="