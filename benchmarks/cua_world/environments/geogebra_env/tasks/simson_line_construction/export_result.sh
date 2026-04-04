#!/bin/bash
# Export script for Simson Line Construction
# Extracts data from the saved .ggb file (ZIP archive) and analyzes it using Python
set -o pipefail

# Fallback result creation
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "{ \"error\": \"Export script failed\", \"file_found\": false, \"task_start_time\": 0 }" > /tmp/task_result.json
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Simson Line Result ==="

# 1. Take final screenshot (for VLM verification)
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze results using Python
# We embed the Python script here to run inside the container
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import glob
import math

# Configuration
EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/simson_line.ggb"
TASK_START_FILE = "/tmp/task_start_time"

# Initialize result dictionary
result = {
    "file_found": False,
    "file_created_during_task": False,
    "file_path": "",
    "timestamp": time.time(),
    "has_circumcircle": False,
    "has_point_on_circle": False,
    "num_perpendiculars": 0,
    "has_simson_line": False,
    "has_annotation": False,
    "vertices_found": 0,
    "vertex_details": [],
    "commands_used": [],
    "error": None
}

try:
    # Get task start time
    start_time = 0
    if os.path.exists(TASK_START_FILE):
        with open(TASK_START_FILE, 'r') as f:
            start_time = int(f.read().strip())
    
    # Locate the file (check specific path, then search recursively)
    target_file = None
    if os.path.exists(EXPECTED_FILE):
        target_file = EXPECTED_FILE
    else:
        # Fallback: find any recently created .ggb file
        files = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
        files.sort(key=os.path.getmtime, reverse=True)
        for f in files:
            if os.path.getmtime(f) > start_time:
                target_file = f
                break
    
    if target_file:
        result["file_found"] = True
        result["file_path"] = target_file
        mtime = os.path.getmtime(target_file)
        
        if mtime >= start_time:
            result["file_created_during_task"] = True
        
        # Analyze GeoGebra XML content
        # .ggb files are ZIP archives containing geogebra.xml
        try:
            with zipfile.ZipFile(target_file, 'r') as zf:
                if 'geogebra.xml' in zf.namelist():
                    xml_content = zf.read('geogebra.xml').decode('utf-8', errors='replace')
                    
                    # 1. Check for Commands
                    # Extract command names like <command name="Circle">
                    commands = re.findall(r'<command name="([^"]+)"', xml_content)
                    result["commands_used"] = list(set(commands))
                    
                    # 2. Check for Circumcircle
                    # Look for Circle command with 3 arguments or explicit name
                    has_circle_cmd = 'Circle' in result["commands_used"] or \
                                     'Circumcircle' in result["commands_used"] or \
                                     'CircumcircularArc' in result["commands_used"]
                    
                    # Also check elements directly
                    has_conic = '<element type="conic"' in xml_content
                    result["has_circumcircle"] = has_circle_cmd or has_conic
                    
                    # 3. Check for Perpendiculars
                    # Look for PerpendicularLine, OrthogonalLine
                    perp_cmds = [c for c in commands if c in ['PerpendicularLine', 'OrthogonalLine', 'LineBisector']]
                    result["num_perpendiculars"] = len(perp_cmds)
                    # Also count elements directly if created via tools
                    if result["num_perpendiculars"] == 0:
                        # GeoGebra sometimes saves tool actions differently, but usually as commands
                        # Rough check for number of lines dependent on point P
                        pass
                        
                    # 4. Check for Point on Circle
                    # Look for Point command with circle as input OR PointOn/PointIn
                    has_point_cmd = 'Point' in result["commands_used"]
                    has_point_on = 'PointOn' in result["commands_used"] or 'PointIn' in result["commands_used"]
                    
                    # Check for dependency: Point P dependent on Circle c
                    # This is complex to parse via regex, so we use a heuristic:
                    # Does a point exist that is not a free point (A, B, C)?
                    # We'll rely on the verification of "PointOn" command or robust scoring in verifier
                    result["has_point_on_circle"] = has_point_on or (has_point_cmd and has_circle_cmd)
                    
                    # 5. Check for Simson Line
                    # Look for Line command through points
                    has_line = 'Line' in result["commands_used"]
                    result["has_simson_line"] = has_line
                    
                    # 6. Check for Annotation
                    result["has_annotation"] = '<element type="text"' in xml_content
                    
                    # 7. Check Triangle Vertices (A, B, C)
                    # Parse point coordinates from XML
                    # Format: <coords x="0" y="0" z="1"/>
                    import xml.etree.ElementTree as ET
                    try:
                        root = ET.fromstring(xml_content)
                        points = []
                        # Scan construction elements
                        construction = root.find(".//construction")
                        if construction is not None:
                            for elem in construction.findall("element"):
                                if elem.get("type") == "point":
                                    label = elem.get("label", "?")
                                    coords = elem.find("coords")
                                    if coords is not None:
                                        try:
                                            x = float(coords.get("x", 0))
                                            y = float(coords.get("y", 0))
                                            z = float(coords.get("z", 1))
                                            # Normalize homogeneous coords
                                            if abs(z) > 1e-6:
                                                points.append({"label": label, "x": x/z, "y": y/z})
                                            else:
                                                points.append({"label": label, "x": x, "y": y})
                                        except ValueError:
                                            pass
                        
                        # Check against expected: A(0,0), B(6,0), C(2,5)
                        expected = [(0,0), (6,0), (2,5)]
                        found_count = 0
                        tolerance = 0.25
                        
                        for ex, ey in expected:
                            match = False
                            for p in points:
                                if abs(p["x"] - ex) < tolerance and abs(p["y"] - ey) < tolerance:
                                    match = True
                                    result["vertex_details"].append(f"Found ({ex},{ey}) as {p['label']}")
                                    break
                            if match:
                                found_count += 1
                        
                        result["vertices_found"] = found_count
                        
                    except Exception as e:
                        result["error"] = f"XML parsing error: {str(e)}"

        except Exception as e:
            result["error"] = f"ZIP processing error: {str(e)}"

except Exception as e:
    result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# 3. Secure the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="