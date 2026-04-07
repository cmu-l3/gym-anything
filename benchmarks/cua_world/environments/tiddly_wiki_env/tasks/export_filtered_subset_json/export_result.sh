#!/bin/bash
echo "=== Exporting export_filtered_subset_json result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

FILE_PATH="/home/ga/Documents/Habitable_Terrestrials.json"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$FILE_PATH" 2>/dev/null || echo "0")
fi

# Use Python to safely parse the TiddlyWiki JSON array output and prevent jq edge cases
PYTHON_PARSE_RESULT=$(python3 << 'PYEOF'
import json
import sys
import os

filepath = "/home/ga/Documents/Habitable_Terrestrials.json"
res = {"valid": False, "count": 0, "titles": [], "has_fields": False}

if os.path.exists(filepath):
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
        if isinstance(data, list):
            res["valid"] = True
            res["count"] = len(data)
            res["titles"] = [d.get("title", "") for d in data if isinstance(d, dict)]
            
            # Check if all items retained their custom structural TiddlyWiki fields
            fields_ok = True
            for d in data:
                if not isinstance(d, dict):
                    fields_ok = False
                    break
                if "discovery_year" not in d:
                    fields_ok = False
                    break
            if len(data) > 0:
                res["has_fields"] = fields_ok
            else:
                res["has_fields"] = False
    except Exception as e:
        res["error"] = str(e)

print(json.dumps(res))
PYEOF
)

# Parse Log Tiddler Information
LOG_TITLE="Export Log"
LOG_EXISTS=$(tiddler_exists "$LOG_TITLE")
LOG_TAGS=""
LOG_TEXT=""
LOG_HAS_8="false"
LOG_HAS_SYSTEMLOG="false"

if [ "$LOG_EXISTS" = "true" ]; then
    LOG_TAGS=$(get_tiddler_field "$LOG_TITLE" "tags")
    LOG_TEXT=$(get_tiddler_text "$LOG_TITLE")
    
    echo "$LOG_TAGS" | grep -qi "SystemLog" && LOG_HAS_SYSTEMLOG="true"
    echo "$LOG_TEXT" | grep -q "8" && LOG_HAS_8="true"
fi

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

ESCAPED_LOG_TAGS=$(json_escape "$LOG_TAGS")
ESCAPED_LOG_TEXT=$(json_escape "$LOG_TEXT")

JSON_RESULT=$(cat << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start_time": $TASK_START,
    "json_data": $PYTHON_PARSE_RESULT,
    "log_exists": $LOG_EXISTS,
    "log_tags": "$ESCAPED_LOG_TAGS",
    "log_has_systemlog": $LOG_HAS_SYSTEMLOG,
    "log_has_8": $LOG_HAS_8,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/task_result.json"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="