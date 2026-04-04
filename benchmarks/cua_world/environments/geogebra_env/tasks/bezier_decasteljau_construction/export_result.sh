#!/bin/bash
# Export script for Bézier Curve de Casteljau Construction task
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script failed or crashed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Bézier Curve Task Result ==="

# 1. Take Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze the GGB file using Python
# We embed the python script to handle unzip and XML parsing robustly
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import math
import xml.etree.ElementTree as ET

EXPECTED_DIR = "/home/ga/Documents/GeoGebra/projects"
EXPECTED_FILENAME = "bezier_decasteljau.ggb"
TASK_START_TIME = 0

try:
    with open("/tmp/task_start_time", "r") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "control_points_found": 0,
    "correct_control_coords": [],
    "slider_found": False,
    "segments_count": 0,
    "intermediate_points_count": 0,
    "curve_command_found": False,
    "xml_extract_success": False
}

# Find the file
target_path = os.path.join(EXPECTED_DIR, EXPECTED_FILENAME)
found_file = None

if os.path.exists(target_path):
    found_file = target_path
else:
    # Look for any recent ggb file
    files = glob.glob(os.path.join(EXPECTED_DIR, "*.ggb"))
    if files:
        # Sort by modification time
        files.sort(key=os.path.getmtime, reverse=True)
        found_file = files[0]

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    mtime = os.path.getmtime(found_file)
    if mtime >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # Extract and Parse XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
                result["xml_extract_success"] = True
                
                # Parse XML
                root = ET.fromstring(xml_content)
                
                # 1. Check Control Points P0(0,0), P1(1,3), P2(4,3), P3(5,0)
                # GeoGebra stores points in <element type="point">...<coords x="..." y="..." z="..."/>
                # Note: z is homogeneous coordinate, usually 1.0 for 2D points.
                points = []
                construction = root.find("./construction") or root
                
                for elem in construction.findall(".//element[@type='point']"):
                    coords = elem.find("./coords")
                    if coords is not None:
                        x = float(coords.get('x', 0))
                        y = float(coords.get('y', 0))
                        z = float(coords.get('z', 1))
                        if z != 0:
                            points.append((x/z, y/z))
                
                # Check against expected targets with tolerance
                targets = [(0,0), (1,3), (4,3), (5,0)]
                found_targets = [False] * 4
                tolerance = 0.2
                
                for pt in points:
                    for i, target in enumerate(targets):
                        if not found_targets[i]:
                            dist = math.sqrt((pt[0]-target[0])**2 + (pt[1]-target[1])**2)
                            if dist < tolerance:
                                found_targets[i] = True
                                result["correct_control_coords"].append(target)
                
                result["control_points_found"] = sum(found_targets)
                
                # Count total dependent points (intermediate points)
                # Dependent points usually have an expression/command attached or explicit "expression" tag
                # We simply count points that are NOT the fixed control points roughly
                # A better check is counting points defined by expression
                
                dependent_points = 0
                for cmd in construction.findall(".//command"):
                    # Commands that output points (like Point(Line), Midpoint, or arithmetic operations)
                    name = cmd.get("name", "")
                    if name not in ["CurveCartesian", "Locus", "Segment"]: 
                        output = cmd.find("./output")
                        if output is not None and output.get("a0"):
                             # Check if output is a point element
                             label = output.get("a0")
                             # Find element with this label
                             el = construction.find(f".//element[@label='{label}']")
                             if el is not None and el.get("type") == "point":
                                 dependent_points += 1
                
                # Also check for points defined via expression logic in XML (algebraic updates)
                # Simple heuristic: total points - 4 (control) > 3 implies intermediate structure
                result["intermediate_points_count"] = max(0, len(points) - 4)

                # 2. Check for Slider
                # <element type="numeric"> <value val="..."/> </element>
                # Usually sliders are numeric elements with animation step or min/max
                sliders = 0
                for elem in construction.findall(".//element[@type='numeric']"):
                    # Check if it has a slider range usually implies it's a slider
                    if elem.find("./slider") is not None:
                        sliders += 1
                
                if sliders > 0:
                    result["slider_found"] = True

                # 3. Check for Segments
                segments = len(construction.findall(".//element[@type='segment']"))
                result["segments_count"] = segments

                # 4. Check for Curve or Locus command
                # <command name="CurveCartesian"> or <command name="Locus">
                has_curve = False
                cmds = [c.get("name") for c in construction.findall(".//command")]
                if "CurveCartesian" in cmds or "Locus" in cmds:
                    has_curve = True
                
                result["curve_command_found"] = has_curve

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="