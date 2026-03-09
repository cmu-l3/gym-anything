#!/bin/bash
# Export script for Cooling Tower Modeling task
set -o pipefail

# Ensure fallback result
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "points_found": 0,
    "has_polynomial": false,
    "has_surface": false,
    "has_integral": false,
    "has_annotation": false,
    "volume_value": 0,
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

echo "=== Exporting Cooling Tower Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run python script to analyze the .ggb file (which is a zip)
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/cooling_tower.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "file_path": "",
    "points_found": 0,
    "points_correct": False,
    "has_polynomial": False,
    "has_surface": False,
    "has_integral": False,
    "volume_value": 0.0,
    "has_annotation": False,
    "annotation_text": "",
    "commands": []
}

# Find file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for any recent ggb file
    candidates = sorted(glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True), key=os.path.getmtime, reverse=True)
    if candidates:
        found_file = candidates[0]

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    mtime = os.path.getmtime(found_file)
    if TASK_START_TIME > 0 and int(mtime) >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Parse XML
                root = ET.fromstring(xml_content)
                
                # Check points
                points = []
                for elem in root.findall(".//element[@type='point']"):
                    coords = elem.find("coords")
                    if coords is not None:
                        x = float(coords.get('x', 0))
                        y = float(coords.get('y', 0))
                        # GeoGebra 3D points might use z
                        z_val = float(coords.get('z', 1)) 
                        if z_val != 0: # Homogeneous coords
                            x = x/z_val
                            y = y/z_val
                        points.append((x, y))
                
                # Target points: (0, 46), (85, 26), (114, 27.5)
                # Allow tolerance
                targets = [(0, 46), (85, 26), (114, 27.5)]
                found_targets = 0
                for tx, ty in targets:
                    for px, py in points:
                        if abs(tx-px) < 1.0 and abs(ty-py) < 1.0:
                            found_targets += 1
                            break
                result["points_found"] = found_targets
                result["points_correct"] = (found_targets >= 3)

                # Check commands
                commands = []
                for cmd in root.findall(".//command"):
                    name = cmd.get("name")
                    commands.append(name)
                    
                    if name == "Polynomial" or name == "FitPoly":
                        result["has_polynomial"] = True
                    
                    if name == "Surface":
                        result["has_surface"] = True
                        
                    if name == "Integral":
                        result["has_integral"] = True
                        # Try to get value
                        output = cmd.find("output")
                        if output is not None:
                            label = output.get("a0")
                            # Find element with this label to get value
                            for elem in root.findall(".//element"):
                                if elem.get("label") == label:
                                    val_elem = elem.find("value")
                                    if val_elem is not None:
                                        try:
                                            result["volume_value"] = float(val_elem.get("val", 0))
                                        except:
                                            pass
                result["commands"] = list(set(commands))

                # Check text annotations
                for elem in root.findall(".//element[@type='text']"):
                    # Check start string or value
                    # GeoGebra stores text often as startstring or definition
                    # Simple check: is there a text element?
                    result["has_annotation"] = True
                    # Try to extract text content roughly
                    result["annotation_text"] = "Found text element"

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json