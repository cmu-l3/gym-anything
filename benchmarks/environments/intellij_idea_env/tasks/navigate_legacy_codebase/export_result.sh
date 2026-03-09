#!/bin/bash
echo "=== Exporting Navigate Legacy Codebase result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_FILE="/home/ga/fallback_key.txt"
PROJECT_DIR="/home/ga/IdeaProjects/LegacyAuthSystem"

# 1. Check Output File
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | head -n 1 | tr -d '\n\r')
    
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Source Integrity (Anti-Gaming)
# We want to ensure the agent didn't just modify the code to print the key
# Calculate current checksums
find "$PROJECT_DIR/src/main/java" -name "*.java" -type f -exec md5sum {} \; | sort > /tmp/current_source_checksums.txt

SOURCE_MODIFIED="false"
if ! cmp -s /tmp/initial_source_checksums.txt /tmp/current_source_checksums.txt; then
    SOURCE_MODIFIED="true"
fi

# 3. Check Open Files (via recent files or open editors if possible, hard to get exactly from outside)
# Instead, we rely on screenshot evidence or VLM

# Escape content for JSON
OUTPUT_ESCAPED=$(echo "$OUTPUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_content": $OUTPUT_ESCAPED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "source_modified": $SOURCE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="