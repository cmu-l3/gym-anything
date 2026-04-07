#!/bin/bash
echo "=== Exporting Sky Background Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null && echo "true" || echo "false")

REPORT_FILE="/home/ga/AstroImages/measurements/sky_background_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check report file creation and modification
FILE_EXISTS="false"
CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Parse the report file using Python and generate result JSON
python3 << PYEOF
import json
import os
import re

report_path = "$REPORT_FILE"
file_exists = "$FILE_EXISTS" == "true"
created_during = "$CREATED_DURING_TASK" == "true"
app_running = "$APP_RUNNING" == "true"

result = {
    "report_exists": file_exists,
    "created_during_task": created_during,
    "app_running": app_running,
    "parsed_values": {}
}

if file_exists:
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            
        # Parse key-value pairs (ignoring comments)
        for line in content.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
                
            if ':' in line:
                key, val = line.split(':', 1)
                key = key.strip().lower()
                val = val.strip()
                
                # Try to convert to float/int if possible
                try:
                    # Strip any text after the number just in case
                    num_str = re.search(r'[-+]?\d*\.\d+|\d+', val)
                    if num_str:
                        num_val = float(num_str.group())
                        result["parsed_values"][key] = num_val
                    else:
                        result["parsed_values"][key] = val
                except ValueError:
                    result["parsed_values"][key] = val
                    
    except Exception as e:
        result["parse_error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON created:"
cat /tmp/task_result.json

echo "=== Export Complete ==="