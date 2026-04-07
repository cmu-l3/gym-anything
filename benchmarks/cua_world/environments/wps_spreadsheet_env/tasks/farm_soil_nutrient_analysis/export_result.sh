#!/bin/bash
echo "=== Exporting task result ==="

DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

SOIL_FILE="/home/ga/Documents/soil_test_results.xlsx"
INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")
CURRENT_MTIME=$(stat -c %Y "$SOIL_FILE" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
    FILE_MODIFIED="true"
fi

# Export minimal state via JSON, detailed extraction is handled by host verifier
python3 << PYEOF
import json
import os

result = {
    "file_exists": os.path.exists("$SOIL_FILE"),
    "file_modified": $FILE_MODIFIED,
    "error": None
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="