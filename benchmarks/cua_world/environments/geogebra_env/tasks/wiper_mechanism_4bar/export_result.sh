#!/bin/bash
# Export script for Wiper Mechanism Task
set -o pipefail

# Ensure we produce a result file even if something fails
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        cat > /tmp/task_result.json << 'EOF'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script failed or file not found"
}
EOF
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Wiper Mechanism Result ==="

# 1. Take final screenshot (for VLM verification)
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze the GeoGebra file using Python
# We interpret the .ggb (zip) file and parse the geogebra.xml inside
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import math
import glob

# Configuration
EXPECTED_PATH = "/home/ga/Documents/GeoGebra/projects/wiper_mech.ggb"
TASK_START_FILE = "/tmp/task_start_time"

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_created_during_task": False,
    "xml_valid": False,
    "points_found": [],      # List of (x,y) tuples
    "circles_radii": [],     # List of radii found
    "segments_lengths": [],  # List of segment lengths
    "commands_used": [],     # Set of command names
    "has_intersect": False,  # Critical for mechanism logic
    "has_locus_or_trace": False
}

# 1. Locate file
target_file = None
if os.path.exists(EXPECTED_PATH):
    target_file = EXPECTED_PATH
else:
    # Search for any recent .ggb file if exact name mismatch
    files = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
    if files:
        target_file = max(files, key=os.path.getmtime)

if target_file:
    result["file_found"] = True
    result["file_path"] = target_file
    result["file_size"] = os.path.getsize(target_file)
    
    # Check timestamp
    mtime = os.path.getmtime(target_file)
    start_time = 0
    if os.path.exists(TASK_START_FILE):
        with open(TASK_START_FILE) as f:
            start_time = float(f.read().strip())
    
    if mtime >= start_time:
        result["file_created_during_task"] = True

    # 2. Parse GeoGebra XML
    try:
        with zipfile.ZipFile(target_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml = z.read('geogebra.xml').decode('utf-8')
                result["xml_valid"] = True
                
                # A. Extract Points
                # <coords x="8" y="0" z="1"/>
                # GeoGebra uses homogeneous coords (x/z, y/z)
                point_matches = re.findall(r'<element type="point"[^>]*>.*?<coords x="([^"]+)" y="([^"]+)" z="([^"]+)"', xml, re.DOTALL)
                for px, py, pz in point_matches:
                    try:
                        z_val = float(pz)
                        if abs(z_val) > 1e-6:
                            result["points_found"].append((float(px)/z_val, float(py)/z_val))
                    except:
                        pass
                
                # B. Extract Circle Radii (Constraints)
                # Look for command inputs like Circle(Point, Radius)
                # <command name="Circle"> <input a0="A" a1="3"/> ...
                circle_cmds = re.findall(r'<command name="Circle">.*?<input [^>]*a1="([^"]+)"', xml, re.DOTALL)
                for radius in circle_cmds:
                    try:
                        result["circles_radii"].append(float(radius))
                    except:
                        pass
                
                # C. Extract Commands
                cmds = re.findall(r'<command name="([^"]+)"', xml)
                result["commands_used"] = list(set(cmds))
                
                if "Intersect" in result["commands_used"]:
                    result["has_intersect"] = True
                    
                if "Locus" in result["commands_used"] or 'trace="true"' in xml:
                    result["has_locus_or_trace"] = True

                # D. Check for Segment lengths (via command or definition)
                # This is harder to parse directly from XML commands, but we can verify 
                # structure via the points found if they match the mechanism topology.
                
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json