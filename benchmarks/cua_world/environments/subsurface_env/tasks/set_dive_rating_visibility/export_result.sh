#!/bin/bash
set -euo pipefail

echo "=== Exporting Set Dive Rating and Visibility task result ==="

export DISPLAY="${DISPLAY:-:1}"

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_PATH="/home/ga/Documents/dives.ssrf"

# Use Python to safely extract file data and parse XML into JSON
python3 - <<EOF
import json, os, hashlib
import xml.etree.ElementTree as ET

output_path = "$OUTPUT_PATH"
task_start = $TASK_START
task_end = $TASK_END
initial_hash = "$INITIAL_HASH"

result = {
    "task_start": task_start,
    "task_end": task_end,
    "initial_hash": initial_hash,
    "file_exists": False,
    "file_modified": False,
    "current_hash": "",
    "mtime": 0,
    "dive_found": False,
    "rating": "0",
    "visibility": "0",
    "total_dives": 0,
    "xml_error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["mtime"] = os.path.getmtime(output_path)
    
    with open(output_path, "rb") as f:
        result["current_hash"] = hashlib.md5(f.read()).hexdigest()

    # Determine if file was actively modified
    result["file_modified"] = (result["current_hash"] != result["initial_hash"]) and (result["mtime"] > result["task_start"])

    # Parse XML safely to extract rating and visibility
    try:
        tree = ET.parse(output_path)
        root = tree.getroot()
        dives = list(root.iter('dive'))
        result["total_dives"] = len(dives)

        for d in dives:
            if d.get('number') == '2':
                result["dive_found"] = True
                result["rating"] = d.get('rating', '0')
                result["visibility"] = d.get('visibility', '0')
                break
    except Exception as e:
        result["xml_error"] = str(e)

# Save result safely
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json