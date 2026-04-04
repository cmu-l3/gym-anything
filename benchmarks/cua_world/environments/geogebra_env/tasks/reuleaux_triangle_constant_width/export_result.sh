#!/bin/bash
# Export script for Reuleaux Triangle task
set -o pipefail

# Ensure fallback result
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
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

echo "=== Exporting Reuleaux Triangle Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze the GeoGebra file using Python
# We use an embedded python script to unzip the .ggb and parse the XML
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import math
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/reuleaux_triangle.ggb"
TASK_START_TIME = 0

try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "points_found": [],
    "arcs_found": 0,
    "text_found": [],
    "commands": [],
    "correct_vertices": 0,
    "timestamp": int(time.time())
}

# Check file existence
if os.path.exists(EXPECTED_FILE):
    result["file_found"] = True
    mtime = os.path.getmtime(EXPECTED_FILE)
    if mtime >= TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # Parse GGB (Zip archive)
    try:
        with zipfile.ZipFile(EXPECTED_FILE, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
                
                # Use ElementTree for robust parsing
                root = ET.fromstring(xml_content)
                construction = root.find('construction')
                if construction is None:
                    construction = root
                
                # Analyze Points
                for elem in construction.findall(".//element[@type='point']"):
                    coords = elem.find("coords")
                    label = elem.get("label", "?")
                    if coords is not None:
                        try:
                            x = float(coords.get("x", 0))
                            y = float(coords.get("y", 0))
                            z_coord = float(coords.get("z", 1))
                            if abs(z_coord) > 1e-6:
                                result["points_found"].append({
                                    "label": label,
                                    "x": x/z_coord, 
                                    "y": y/z_coord
                                })
                        except ValueError:
                            pass

                # Analyze Commands (looking for CircularArc)
                # GeoGebra stores arcs often as commands or elements
                # command name="CircularArc"
                arcs = construction.findall(".//command[@name='CircularArc']")
                result["arcs_found"] = len(arcs)
                
                # Also check for 'Arc' command which is sometimes used
                if result["arcs_found"] == 0:
                    result["arcs_found"] = len(construction.findall(".//command[@name='Arc']"))

                # Analyze Text
                for elem in construction.findall(".//element[@type='text']"):
                    # GeoGebra 6 often puts text in specific val attribute or separate structure
                    # We check various text storage methods
                    # 1. The 'val' attribute of the element (if simple)
                    # 2. A child <startPoint> or similar isn't text content
                    # 3. Often the text is just in the element definition if not a command
                    # Actually, let's just grep the XML string for text content for simplicity and robustness
                    pass
                
                # Regex for text content is often safer than XML parsing for arbitrary text tags
                # Look for "constant" and "width" in the raw XML to be safe
                text_matches = re.findall(r'constant\s+width', xml_content, re.IGNORECASE)
                if text_matches:
                    result["text_found"].append("constant width")
                
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="