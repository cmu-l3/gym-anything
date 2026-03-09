#!/bin/bash
# Export script for Soda Can Optimization task
set -o pipefail

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
    "task_end_time": 0,
    "has_cylinder": false,
    "has_cost_function": false,
    "has_volume_const": false,
    "radius_value": 0,
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

echo "=== Exporting Soda Can Optimization Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python to analyze the GGB file (it is a ZIP containing XML)
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/soda_can_opt.ggb"
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
    "has_cylinder": False,
    "has_cost_function": False,
    "has_volume_const": False,
    "radius_value": 0.0,
    "height_value": 0.0,
    "num_sliders": 0,
    "num_functions": 0,
    "xml_commands": [],
    "xml_dump_snippets": [] # For debugging/logging
}

# Find the file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Fallback: check recent files
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
                
                # Basic counters
                result["num_sliders"] = len(re.findall(r'<element type="numeric"', xml_content))
                result["num_functions"] = len(re.findall(r'<element type="function"', xml_content))
                
                # Check for Cylinder (can be command or element)
                has_cyl_cmd = bool(re.search(r'<command name="Cylinder"', xml_content, re.IGNORECASE))
                # GeoGebra might store 3D objects as elements of type 'quadric'
                has_quadric = bool(re.search(r'<element type="quadric"', xml_content, re.IGNORECASE))
                result["has_cylinder"] = has_cyl_cmd or has_quadric

                # Parse XML to find values and logic
                try:
                    root = ET.fromstring(xml_content)
                    
                    # 1. Check for Volume = 355
                    # Look for numeric definition with val=355
                    for elem in root.iter('element'):
                        if elem.get('type') == 'numeric':
                            val_node = elem.find('value')
                            if val_node is not None:
                                try:
                                    val = float(val_node.get('val', 0))
                                    if abs(val - 355.0) < 0.1:
                                        result["has_volume_const"] = True
                                except: pass
                    
                    # 2. Check radius slider value
                    # We look for a numeric element named 'r' or just the current value of sliders
                    # Heuristic: find any slider between 2.0 and 4.0
                    for elem in root.iter('element'):
                        if elem.get('type') == 'numeric':
                            # Check if it is a slider (usually has show/animation tags)
                            if elem.find('slider') is not None or elem.get('label') == 'r':
                                val_node = elem.find('value')
                                if val_node is not None:
                                    val = float(val_node.get('val', 0))
                                    # If label is specifically r, take it. Else keep last valid candidate.
                                    if elem.get('label') == 'r':
                                        result["radius_value"] = val
                                    elif 2.0 < val < 4.0:
                                        # Candidate for being the radius if 'r' not named explicitly
                                        if result["radius_value"] == 0: 
                                            result["radius_value"] = val

                    # 3. Check Cost Function logic
                    # We search for "2.2" inside expression attributes of functions
                    for elem in root.iter('expression'):
                        exp_str = elem.get('exp', '')
                        if '2.2' in exp_str or '11/5' in exp_str:
                            result["has_cost_function"] = True
                    
                    # Also check CasCells if they used CAS
                    if not result["has_cost_function"]:
                        if '2.2' in xml_content:
                             result["has_cost_function"] = True # Fallback loose check

                except Exception as e:
                    result["xml_dump_snippets"].append(f"XML Parse Error: {str(e)}")

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json