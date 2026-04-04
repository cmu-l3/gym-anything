#!/bin/bash
# Export script for L-Beam Centroid Statics task
set -o pipefail

# Trap to ensure JSON is always created
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        echo '{"error": "Export script failed"}' > /tmp/task_result.json
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting L-Beam Centroid Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths
PROJECT_DIR="/home/ga/Documents/GeoGebra/projects"
TARGET_FILE="$PROJECT_DIR/l_shape_statics.ggb"
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 3. Use Python to analyze the .ggb file (which is a zip)
python3 << 'PYEOF'
import os
import sys
import glob
import time
import zipfile
import json
import re
import math
import shutil

# Config
target_file = "/home/ga/Documents/GeoGebra/projects/l_shape_statics.ggb"
search_dir = "/home/ga/Documents/GeoGebra"
task_start_time = 0
try:
    with open("/tmp/task_start_time", "r") as f:
        task_start_time = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "points": [],
    "polygons": [],
    "angles": [],
    "lines": [],
    "xml_content": ""
}

# Find file (exact match or recent)
found_path = None
if os.path.exists(target_file):
    found_path = target_file
else:
    # Look for any recent ggb file
    files = glob.glob(os.path.join(search_dir, "**/*.ggb"), recursive=True)
    files = sorted(files, key=os.path.getmtime, reverse=True)
    if files:
        found_path = files[0]

if found_path:
    result["file_found"] = True
    mtime = os.path.getmtime(found_path)
    if mtime >= task_start_time:
        result["file_created_during_task"] = True
    
    # Extract XML
    try:
        with zipfile.ZipFile(found_path, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml = z.read('geogebra.xml').decode('utf-8')
                result["xml_content"] = "XML_EXTRACTED" # Flag, don't dump huge string
                
                # Simple Regex Parsing for verification
                
                # 1. Points: <element type="point" label="G"> ... <coords x="2" y="3" z="1"/>
                point_matches = re.findall(r'<element type="point"[^>]*label="([^"]*)"[^>]*>.*?<coords x="([^"]*)" y="([^"]*)" z="([^"]*)"', xml, re.DOTALL)
                for label, x, y, z in point_matches:
                    try:
                        zf = float(z)
                        if abs(zf) > 1e-6:
                            result["points"].append({
                                "label": label,
                                "x": float(x)/zf,
                                "y": float(y)/zf
                            })
                    except:
                        pass
                
                # 2. Polygons: <element type="polygon" ...>
                # We want to check area. GeoGebra usually stores value attribute for numeric objects
                poly_matches = re.findall(r'<element type="polygon"[^>]*label="([^"]*)"[^>]*>.*?<value val="([^"]*)"', xml, re.DOTALL)
                for label, val in poly_matches:
                     result["polygons"].append({
                         "label": label,
                         "value": float(val)
                     })
                     
                # 3. Angles: <element type="angle" ...>
                angle_matches = re.findall(r'<element type="angle"[^>]*label="([^"]*)"[^>]*>.*?<value val="([^"]*)"', xml, re.DOTALL)
                for label, val in angle_matches:
                    # GeoGebra stores angles in radians
                    rad = float(val)
                    deg = math.degrees(rad)
                    result["angles"].append({
                        "label": label,
                        "radians": rad,
                        "degrees": deg
                    })
                
                # 4. Lines: <element type="line" ...>
                line_matches = re.findall(r'<element type="line"[^>]*label="([^"]*)"[^>]*>.*?<coords x="([^"]*)" y="([^"]*)" z="([^"]*)"', xml, re.DOTALL)
                for label, x, y, z in line_matches:
                    # Line equation: x*X + y*Y + z = 0
                    result["lines"].append({
                        "label": label,
                        "a": float(x),
                        "b": float(y),
                        "c": float(z)
                    })
                    
    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json