#!/bin/bash
echo "=== Exporting Biomechanics Gait Viz Results ==="

# Source task utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze the saved .ggb file using Python
# We need to check inside the zip for geogebra.xml and parse it
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time

# Paths
project_path = "/home/ga/Documents/GeoGebra/projects/gait_viz.ggb"
task_start_file = "/tmp/task_start_time"
output_json = "/tmp/task_result.json"

result = {
    "file_exists": False,
    "file_valid_zip": False,
    "file_created_during_task": False,
    "lists_count": 0,
    "slider_found": False,
    "element_command_used": False,
    "segments_count": 0,
    "points_count": 0,
    "xml_extract_success": False
}

# 1. Check File Existence & Timestamp
if os.path.exists(project_path):
    result["file_exists"] = True
    
    # Check modification time
    try:
        with open(task_start_file, 'r') as f:
            start_time = int(f.read().strip())
        
        mtime = os.path.getmtime(project_path)
        if mtime >= start_time:
            result["file_created_during_task"] = True
    except Exception as e:
        print(f"Timestamp check error: {e}")

    # 2. Analyze Content (Unzip & Parse XML)
    try:
        with zipfile.ZipFile(project_path, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                result["file_valid_zip"] = True
                xml_content = z.read('geogebra.xml').decode('utf-8')
                result["xml_extract_success"] = True
                
                # A. Check for Lists (looking for <element type="list">)
                # Simple regex count
                lists = re.findall(r'<element type="list"', xml_content)
                result["lists_count"] = len(lists)
                
                # B. Check for Slider (looking for <element type="numeric"> ... <slider ... />)
                # Heuristic: look for slider tag inside numeric element, or just existence of slider tag
                if '<slider' in xml_content and '<element type="numeric"' in xml_content:
                    result["slider_found"] = True
                
                # C. Check for Element command (linking list to geometry)
                # Look for command name="Element"
                if 'command name="Element"' in xml_content:
                    result["element_command_used"] = True
                
                # D. Check for Geometry (Points and Segments)
                result["points_count"] = len(re.findall(r'<element type="point"', xml_content))
                result["segments_count"] = len(re.findall(r'<element type="segment"', xml_content))
                
    except zipfile.BadZipFile:
        print("Invalid GGB file (not a zip)")
    except Exception as e:
        print(f"Error parsing GGB: {e}")

# Save Result
with open(output_json, 'w') as f:
    json.dump(result, f)

print("Analysis complete. JSON saved.")
PYEOF

# Move result to safe location and ensure permissions
cp /tmp/task_result.json /tmp/safe_task_result.json
chmod 666 /tmp/safe_task_result.json
mv /tmp/safe_task_result.json /tmp/task_result.json

echo "=== Export Complete ==="