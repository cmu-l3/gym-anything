#!/bin/bash
set -e

echo "=== Exporting brand_template_creation result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/brand_template_creation_start_ts 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/apex_letterhead.ott"
OUTPUT_EXISTS=false
FILE_CREATED_DURING_TASK=false
OUTPUT_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS=true
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

take_screenshot /tmp/brand_template_creation_end.png

python3 <<PY
import json

with open("/tmp/brand_template_creation_result.json", "w", encoding="utf-8") as f:
    json.dump(
        {
            "output_exists": "${OUTPUT_EXISTS}".lower() == "true",
            "file_created_during_task": "${FILE_CREATED_DURING_TASK}".lower() == "true",
            "output_size_bytes": ${OUTPUT_SIZE},
        },
        f,
        indent=2,
    )
PY

chmod 666 /tmp/brand_template_creation_result.json
cat /tmp/brand_template_creation_result.json
echo "=== Export complete ==="
