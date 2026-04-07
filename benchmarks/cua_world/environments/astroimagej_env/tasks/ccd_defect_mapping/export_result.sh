#!/bin/bash
echo "=== Exporting CCD Defect Mapping Result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

REPORT_FILE="/home/ga/AstroImages/defect_mapping/defect_report.txt"
FILE_CREATED="false"
CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_CREATED="true"
    MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Parse the report file using Python
python3 << PYEOF
import json
import os
import re

report_path = "$REPORT_FILE"
result = {
    "file_created": "$FILE_CREATED" == "true",
    "created_during_task": "$CREATED_DURING_TASK" == "true",
    "parsed_data": {}
}

if result["file_created"]:
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            result["raw_content"] = content
            
            # Parse key-value pairs
            for line in content.splitlines():
                if ':' in line:
                    key, val = line.split(':', 1)
                    key = key.strip().upper()
                    
                    # Extract the first numeric sequence
                    match = re.search(r'[-+]?\d*\.\d+|\d+', val)
                    if match:
                        result["parsed_data"][key] = float(match.group(0))
    except Exception as e:
        result["parse_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

echo "Export Complete. Result:"
cat /tmp/task_result.json