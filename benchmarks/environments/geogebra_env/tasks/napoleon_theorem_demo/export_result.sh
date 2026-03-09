#!/bin/bash
# Export script for Napoleon's Theorem task
# Extracts geometric data from the saved .ggb file for verification

set -e

# Load utils or define fallback
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Napoleon Theorem Result ==="

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Locate the output file
PROJECT_FILE="/home/ga/Documents/GeoGebra/projects/napoleon_theorem.ggb"
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 3. Analyze the GGB file using Python
# We interpret the XML inside the GGB (zip) to find points and polygons
python3 << 'PYEOF'
import zipfile
import os
import time
import json
import xml.etree.ElementTree as ET
import math

file_path = "/home/ga/Documents/GeoGebra/projects/napoleon_theorem.ggb"
task_start_time = int(os.environ.get('TASK_START_TIME', 0))

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "points": [],
    "polygons": [],
    "commands": [],
    "texts": [],
    "napoleon_triangle_found": False
}

if os.path.exists(file_path):
    result["file_exists"] = True
    mtime = os.path.getmtime(file_path)
    if mtime >= task_start_time:
        result["file_created_during_task"] = True
    
    try:
        with zipfile.ZipFile(file_path, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml')
                root = ET.fromstring(xml_content)
                
                # Extract commands used
                for cmd in root.findall(".//command"):
                    name = cmd.get("name")
                    if name:
                        result["commands"].append(name)
                
                # Extract points (coordinates)
                # GeoGebra stores points as <element type="point"> <coords x="..." y="..." z="..."/>
                for elem in root.findall(".//element[@type='point']"):
                    label = elem.get("label", "")
                    coords = elem.find("coords")
                    if coords is not None:
                        x = float(coords.get("x", 0))
                        y = float(coords.get("y", 0))
                        z = float(coords.get("z", 1))
                        if z != 0:
                            result["points"].append({"label": label, "x": x/z, "y": y/z})
                
                # Extract polygons
                for elem in root.findall(".//element[@type='polygon']"):
                    result["polygons"].append(elem.get("label", "poly"))
                    
                # Extract texts (annotations)
                for elem in root.findall(".//element[@type='text']"):
                    # Text content is often in 'val' attribute of start tag or separate
                    # Just counting them is usually enough for 'annotation exists' check
                    result["texts"].append(elem.get("label", "text"))

                # Geometric Verification Logic:
                # Check for Napoleon Triangle side lengths (~4.83)
                # We calculate distances between all pairs of points
                points = result["points"]
                found_napoleon_side = False
                found_count = 0
                
                # We are looking for an equilateral triangle with side approx 4.83
                target_len = 4.83
                tolerance = 0.1
                
                distances = []
                for i in range(len(points)):
                    for j in range(i+1, len(points)):
                        p1 = points[i]
                        p2 = points[j]
                        dist = math.sqrt((p1["x"]-p2["x"])**2 + (p1["y"]-p2["y"])**2)
                        distances.append(dist)
                        if abs(dist - target_len) < tolerance:
                            found_count += 1
                
                # An equilateral triangle has 3 sides of that length
                if found_count >= 3:
                    result["napoleon_triangle_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result to json
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# 4. Secure permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json