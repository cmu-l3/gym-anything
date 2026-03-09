#!/bin/bash
# Export script for LP Crop Optimization task
# Analysis is performed inside the container to ensure robust XML parsing
set -o pipefail

# Ensure fallback result on any failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": false,
    "task_start_time": 0,
    "task_end_time": 0,
    "constraints_found": [],
    "corner_points_found": [],
    "has_feasible_region": false,
    "has_optimal_annotation": false,
    "error": "Export script failed"
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

echo "=== Exporting LP Crop Optimization Result ==="

# 1. Take final screenshot for VLM verification
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis script inside the container
# This is cleaner than trying to parse XML with bash/grep
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import math
import glob
from xml.etree import ElementTree as ET

# Configuration
EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/crop_optimization.ggb"
TASK_START_FILE = "/tmp/task_start_time"

# Initialize result
result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "task_start_time": 0,
    "task_end_time": int(time.time()),
    "constraints_found": [],
    "corner_points_found": [],
    "has_feasible_region": False,
    "has_optimal_annotation": False,
    "xml_dump": ""  # For debugging
}

# Read start time
try:
    with open(TASK_START_FILE, 'r') as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

# Locate file (check expected path, then recent files)
found_path = None
if os.path.exists(EXPECTED_FILE):
    found_path = EXPECTED_FILE
else:
    # Fallback: search for any .ggb created recently
    candidates = glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True)
    candidates.sort(key=os.path.getmtime, reverse=True)
    for c in candidates:
        if result["task_start_time"] > 0 and os.path.getmtime(c) >= result["task_start_time"]:
            found_path = c
            break

if found_path:
    result["file_found"] = True
    result["file_path"] = found_path
    stats = os.stat(found_path)
    result["file_size"] = stats.st_size
    result["file_modified"] = int(stats.st_mtime)
    
    if result["task_start_time"] > 0 and result["file_modified"] >= result["task_start_time"]:
        result["file_created_during_task"] = True

    # Parse .ggb (ZIP archive)
    try:
        with zipfile.ZipFile(found_path, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                result["xml_dump"] = xml_content[:1000] # Debug snippet

                # --- ANALYSIS ---
                
                # 1. Check Constraints (search for coefficients in expressions)
                # Looking for: x+y=240, 2x+y=400, x+3y=480
                # Robust regex for various formats (spaces, * for mult, different order)
                
                # Constraint 1: x + y <= 240
                if re.search(r'x\s*\+\s*y.*240|240.*x.*y', xml_content, re.IGNORECASE):
                    result["constraints_found"].append("land")
                
                # Constraint 2: 2x + y <= 400
                if re.search(r'2\s*\*?\s*x\s*\+\s*y.*400|400.*2\s*\*?\s*x.*y', xml_content, re.IGNORECASE):
                    result["constraints_found"].append("water")
                    
                # Constraint 3: x + 3y <= 480
                if re.search(r'x\s*\+\s*3\s*\*?\s*y.*480|480.*x.*3\s*\*?\s*y', xml_content, re.IGNORECASE):
                    result["constraints_found"].append("labor")

                # 2. Check Corner Points
                # Parse points from XML
                # <element type="point"><coords x="160" y="80" z="1"/></element>
                try:
                    root = ET.fromstring(xml_content)
                    points = []
                    
                    # Extract all points
                    for elem in root.iter('element'):
                        if elem.get('type') == 'point':
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    x = float(coords.get('x', 0))
                                    y = float(coords.get('y', 0))
                                    z = float(coords.get('z', 1))
                                    if abs(z) > 1e-6:
                                        points.append((x/z, y/z))
                                except:
                                    pass
                    
                    # Check against expected corners with tolerance
                    expected_corners = [
                        (0, 0), (200, 0), (160, 80), (120, 120), (0, 160)
                    ]
                    
                    for ex, ey in expected_corners:
                        for px, py in points:
                            if math.sqrt((ex-px)**2 + (ey-py)**2) < 2.0:
                                result["corner_points_found"].append([ex, ey])
                                break
                                
                except Exception as e:
                    print(f"XML Parse Error: {e}")

                # 3. Check Feasible Region
                # Look for polygons or inequalities
                has_poly = len(re.findall(r'<element type="polygon"', xml_content, re.IGNORECASE)) > 0
                has_ineq = len(re.findall(r'inequality', xml_content, re.IGNORECASE)) > 0
                # Check for integral command which is sometimes used for area
                has_integral = "integral" in xml_content.lower()
                
                result["has_feasible_region"] = has_poly or has_ineq or has_integral

                # 4. Check Optimal Annotation
                # Look for text containing key values: 56000 or (160, 80)
                text_elements = re.findall(r'<element type="text".*?</element>', xml_content, re.DOTALL | re.IGNORECASE)
                annotation_found = False
                for txt in text_elements:
                    if "56000" in txt or "56,000" in txt:
                        annotation_found = True
                    if "160" in txt and "80" in txt:
                        annotation_found = True
                    if "optimal" in txt.lower() or "profit" in txt.lower():
                        annotation_found = True
                
                result["has_optimal_annotation"] = annotation_found

    except Exception as e:
        print(f"ZIP Error: {e}")

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="