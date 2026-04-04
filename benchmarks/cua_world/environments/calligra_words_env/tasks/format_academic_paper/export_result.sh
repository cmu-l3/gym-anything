#!/bin/bash
set -e

echo "=== Exporting format_academic_paper result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/format_academic_paper_start_ts 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/origin_of_species.odt"
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

take_screenshot /tmp/format_academic_paper_end.png

python3 <<PY
import json

with open("/tmp/format_academic_paper_result.json", "w", encoding="utf-8") as f:
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

chmod 666 /tmp/format_academic_paper_result.json
cat /tmp/format_academic_paper_result.json
echo "=== Export complete ==="
