#!/bin/bash
# Export script for Pleiades HR Diagram Analysis
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "points_found": [],
    "polygon_found": false,
    "text_found": false,
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Standard screenshot function
take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Python Script to Analyze the .ggb File
python3 << 'PYEOF'
import os
import zipfile
import json
import re
import time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/pleiades_analysis.ggb"
TASK_START_FILE = "/tmp/task_start_time"

result = {
    "file_found": False,
    "file_created_during_task": False,
    "points_found": [],
    "polygon_found": False,
    "text_found": False,
    "main_sequence_text_found": False,
    "timestamp": int(time.time())
}

# Check file existence and timestamp
if os.path.exists(EXPECTED_FILE):
    result["file_found"] = True
    mtime = os.path.getmtime(EXPECTED_FILE)
    
    start_time = 0
    if os.path.exists(TASK_START_FILE):
        with open(TASK_START_FILE, 'r') as f:
            try:
                start_time = int(f.read().strip())
            except:
                pass
    
    if mtime >= start_time:
        result["file_created_during_task"] = True

    # Extract and Parse XML
    try:
        with zipfile.ZipFile(EXPECTED_FILE, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
                
                # Check for specific elements using Regex first (simpler for existence)
                result["polygon_found"] = bool(re.search(r'<element type="polygon"', xml_content) or re.search(r'<command name="Polygon"', xml_content))
                result["text_found"] = bool(re.search(r'<element type="text"', xml_content))
                
                # Check for "Main Sequence" text specifically
                if re.search(r'Main\s*Sequence', xml_content, re.IGNORECASE):
                    result["main_sequence_text_found"] = True

                # Parse Points using ElementTree for coordinates
                try:
                    root = ET.fromstring(xml_content)
                    # Handle GeoGebra XML namespace issues by ignoring them or handling specifically
                    # We'll search all 'element' tags
                    for elem in root.iter('element'):
                        if elem.get('type') == 'point':
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z_val = float(coords.get('z', 1))
                                    
                                    # GeoGebra uses homogeneous coordinates (x, y, z)
                                    # Real x = x/z, Real y = y/z
                                    if z_val != 0:
                                        real_x = x / z_val
                                        real_y = y / z_val
                                        result["points_found"].append({"x": real_x, "y": real_y})
                                except ValueError:
                                    pass
                except Exception as e:
                    print(f"XML Parsing Error: {e}")
                    # Fallback regex for points if XML parsing fails
                    point_matches = re.findall(r'<coords x="([^"]+)" y="([^"]+)" z="([^"]+)"', xml_content)
                    for px, py, pz in point_matches:
                        try:
                            z_val = float(pz)
                            if z_val != 0:
                                result["points_found"].append({
                                    "x": float(px)/z_val,
                                    "y": float(py)/z_val
                                })
                        except:
                            pass

    except Exception as e:
        print(f"Zip/Read Error: {e}")

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

print("Analysis complete. Found points:", len(result["points_found"]))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."