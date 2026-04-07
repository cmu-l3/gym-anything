#!/bin/bash
set -e
echo "=== Exporting Edit Cylinder Gas to Trimix task result ==="

# Record task end time
TASK_END=$(date +%s)

# Take final screenshot
export DISPLAY="${DISPLAY:-:1}"
scrot /tmp/task_final.png 2>/dev/null || import -window root /tmp/task_final.png 2>/dev/null || true

# Run Python script to parse the SSRF file securely and accurately
python3 << 'EOF'
import xml.etree.ElementTree as ET
import json
import os

result = {
    "file_exists": False,
    "file_mtime": 0,
    "file_modified_during_task": False,
    "total_dives": 0,
    "dive2_exists": False,
    "dive2_cyl1_o2": "",
    "dive2_cyl1_he": "",
    "screenshot_path": "/tmp/task_final.png",
    "xml_error": None
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start_time = int(f.read().strip())
except Exception:
    task_start_time = 0

result['task_start_time'] = task_start_time

path = "/home/ga/Documents/dives.ssrf"
if os.path.exists(path):
    result["file_exists"] = True
    result["file_mtime"] = int(os.path.getmtime(path))
    result["file_modified_during_task"] = result["file_mtime"] > task_start_time
    
    try:
        tree = ET.parse(path)
        root = tree.getroot()
        dives = list(root.iter('dive'))
        result["total_dives"] = len(dives)
        
        for dive in dives:
            if dive.get('number') == '2':
                result["dive2_exists"] = True
                cylinders = list(dive.findall('cylinder'))
                if cylinders:
                    cyl = cylinders[0]
                    result["dive2_cyl1_o2"] = cyl.get('o2', '')
                    result["dive2_cyl1_he"] = cyl.get('he', '')
                break
    except Exception as e:
        result["xml_error"] = str(e)

# Write results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
EOF

# Ensure appropriate permissions on the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="