#!/bin/bash
echo "=== Exporting messier_marathon_sprint results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Collect FITS info from the marathon directory tree
FITS_INFO=$(python3 -c "
import os, json, glob

base = '/home/ga/Images/marathon'
files = []
if os.path.exists(base):
    for root, dirs, filenames in os.walk(base):
        for filename in filenames:
            if filename.lower().endswith(('.fits', '.fit')):
                path = os.path.join(root, filename)
                try:
                    stat = os.stat(path)
                    # Extract parent directory name (e.g. M1, M13)
                    parent_dir = os.path.basename(root)
                    files.append({
                        'name': filename,
                        'dir': parent_dir,
                        'size': stat.st_size,
                        'mtime': stat.st_mtime
                    })
                except Exception as e:
                    pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Check log file
LOG_PATH="/home/ga/Documents/marathon_log.txt"
LOG_EXISTS="false"
LOG_MTIME=0
LOG_B64=""

if [ -f "$LOG_PATH" ]; then
    LOG_EXISTS="true"
    LOG_MTIME=$(stat -c %Y "$LOG_PATH" 2>/dev/null || echo "0")
    LOG_B64=$(head -n 100 "$LOG_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# Check sky view
SKY_PATH="/home/ga/Images/marathon/sky_view_m101.png"
SKY_EXISTS="false"
SKY_SIZE=0
SKY_MTIME=0

if [ -f "$SKY_PATH" ]; then
    SKY_EXISTS="true"
    SKY_MTIME=$(stat -c %Y "$SKY_PATH" 2>/dev/null || echo "0")
    SKY_SIZE=$(stat -c %s "$SKY_PATH" 2>/dev/null || echo "0")
fi

LOG_EXISTS_PY=$([ "$LOG_EXISTS" = "true" ] && echo "True" || echo "False")
SKY_EXISTS_PY=$([ "$SKY_EXISTS" = "true" ] && echo "True" || echo "False")

# Write to JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "log_exists": $LOG_EXISTS_PY,
    "log_mtime": $LOG_MTIME,
    "log_b64": "$LOG_B64",
    "sky_exists": $SKY_EXISTS_PY,
    "sky_size": $SKY_SIZE,
    "sky_mtime": $SKY_MTIME
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="