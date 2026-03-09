#!/bin/bash
# Export script for Mars Elliptical Orbit task
set -o pipefail

# Trap to ensure fallback JSON is always created
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": false,
    "task_start_time": 0,
    "task_end_time": 0,
    "xml_extracted": false,
    "points": [],
    "conics": [],
    "texts": [],
    "commands": [],
    "error": "Export script failed to run completion logic"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utilities if present
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Results ==="

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python extraction logic
# We use Python to parse the GeoGebra XML structure directly
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import xml.etree.ElementTree as ET
import glob

# Configuration
PROJECT_DIR = "/home/ga/Documents/GeoGebra/projects"
EXPECTED_FILE = os.path.join(PROJECT_DIR, "mars_orbit.ggb")
TASK_START_FILE = "/tmp/task_start_time"

# Get task start time
task_start_time = 0
try:
    if os.path.exists(TASK_START_FILE):
        with open(TASK_START_FILE, 'r') as f:
            task_start_time = int(f.read().strip())
except:
    pass

# Initialize result structure
result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "task_start_time": task_start_time,
    "task_end_time": int(time.time()),
    "xml_extracted": False,
    "points": [],       # List of {label, x, y}
    "conics": [],       # List of {label, type, command}
    "texts": [],        # List of {text_content}
    "commands": [],     # List of command names
    "screenshot_path": "/tmp/task_final.png"
}

# Find the file (prioritize expected name, fallback to recent .ggb)
target_file = None
if os.path.exists(EXPECTED_FILE):
    target_file = EXPECTED_FILE
else:
    # Find most recent .ggb file modified after task start
    candidates = glob.glob(os.path.join(PROJECT_DIR, "*.ggb"))
    candidates.sort(key=os.path.getmtime, reverse=True)
    if candidates:
        last_mod = os.path.getmtime(candidates[0])
        if last_mod >= task_start_time:
            target_file = candidates[0]

if target_file:
    result["file_found"] = True
    result["file_path"] = target_file
    result["file_size"] = os.path.getsize(target_file)
    mod_time = int(os.path.getmtime(target_file))
    result["file_modified"] = mod_time
    result["file_created_during_task"] = (mod_time >= task_start_time)

    # Extract and parse XML
    try:
        with zipfile.ZipFile(target_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                result["xml_extracted"] = True
                
                # Parse XML
                root = ET.fromstring(xml_content)
                construction = root.find(".//construction")
                
                if construction is not None:
                    # Extract Points
                    for elem in construction.findall(".//element[@type='point']"):
                        label = elem.get('label', '')
                        coords = elem.find('coords')
                        if coords is not None:
                            try:
                                x = float(coords.get('x', 0))
                                y = float(coords.get('y', 0))
                                z_coord = float(coords.get('z', 1))
                                # Handle homogeneous coordinates
                                if abs(z_coord) > 1e-6:
                                    x /= z_coord
                                    y /= z_coord
                                result["points"].append({"label": label, "x": x, "y": y})
                            except ValueError:
                                pass
                                
                    # Extract Conics (Circle, Ellipse)
                    for elem in construction.findall(".//element[@type='conic']"):
                        label = elem.get('label', '')
                        result["conics"].append({"label": label, "type": "conic"})
                        
                    # Extract Text
                    for elem in construction.findall(".//element[@type='text']"):
                        # GeoGebra text often in <startPoint> or separate definition
                        # We just check for existence or attributes here might need deeper look
                        # Often text content is not directly in attributes but in structure
                        # We'll rely on command scan for 'Text' or try to find content
                        pass
                        
                    # Scan commands to link to objects
                    for cmd in construction.findall(".//command"):
                        name = cmd.get('name', '')
                        result["commands"].append(name)
                        
                        # Check inputs/outputs for more detail if needed
                        
                    # Crude text extraction from XML string for verification
                    text_matches = re.findall(r'string="([^"]+)"', xml_content)
                    result["texts"] = text_matches

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export logic completed.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json