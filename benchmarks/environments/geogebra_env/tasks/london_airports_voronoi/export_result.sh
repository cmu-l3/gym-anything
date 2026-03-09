#!/bin/bash
# Export script for London Airports Voronoi task
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script crashed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Results ==="

# 1. Capture final screenshot for VLM
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze the GGB file using Python
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/london_airports_voronoi.ggb"
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
    "points_found": [],  # List of {x, y, label}
    "list_command_found": False,
    "voronoi_command_found": False,
    "text_annotation_found": False,
    "xml_valid": False
}

# Find file (prefer exact match, fallback to recent)
target_file = None
if os.path.exists(EXPECTED_FILE):
    target_file = EXPECTED_FILE
else:
    # Look for any recent GGB file
    candidates = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
    candidates.sort(key=os.path.getmtime, reverse=True)
    for c in candidates:
        if os.path.getmtime(c) >= TASK_START_TIME:
            target_file = c
            break

if target_file:
    result["file_found"] = True
    result["file_path"] = target_file
    mtime = os.path.getmtime(target_file)
    result["file_created_during_task"] = (mtime >= TASK_START_TIME)

    try:
        with zipfile.ZipFile(target_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                result["xml_valid"] = True
                
                # Parse XML for verification
                root = ET.fromstring(xml_content)
                construction = root.find('.//construction')
                
                # Check 1: Extract all points
                # GeoGebra stores points in <element type="point"> with <coords x="..." y="..." z="1"/>
                if construction is not None:
                    for elem in construction.findall('element'):
                        if elem.get('type') == 'point':
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z = float(coords.get('z', 1))
                                    if abs(z) > 1e-6:
                                        result["points_found"].append({
                                            "x": x/z, 
                                            "y": y/z, 
                                            "label": elem.get('label', '')
                                        })
                                except:
                                    pass
                        
                        # Check 4: Text annotation
                        if elem.get('type') == 'text':
                            result["text_annotation_found"] = True
                
                # Check 2 & 3: Commands
                # Voronoi is a command <command name="Voronoi">
                if re.search(r'<command name="Voronoi"', xml_content, re.IGNORECASE):
                    result["voronoi_command_found"] = True
                
                # Check for list creation. Either a command "Sequence" or just an expression definition
                # GeoGebra lists are <expression label="list1" exp="{...}"/> or <element type="list">
                if re.search(r'<element type="list"', xml_content, re.IGNORECASE) or \
                   re.search(r'exp="\{.*,.*\}"', xml_content):
                    result["list_command_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete. Points found:", len(result["points_found"]))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="