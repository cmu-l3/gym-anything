#!/bin/bash
echo "=== Exporting Retrieve Archive Entry results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_FILE="/home/ga/recovered_config.properties"
EXPECTED_FILE="/tmp/expected_config.txt"

# check output file
OUTPUT_EXISTS="false"
OUTPUT_MATCH="false"
FILE_CREATED_DURING_TASK="false"
ACTUAL_CONTENT=""
EXPECTED_CONTENT=""

if [ -f "$EXPECTED_FILE" ]; then
    EXPECTED_CONTENT=$(cat "$EXPECTED_FILE")
fi

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    ACTUAL_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Compare content (ignoring trailing whitespace/newlines)
    # We use python for safer string comparison
    OUTPUT_MATCH=$(python3 -c "
import sys
try:
    actual = '''$ACTUAL_CONTENT'''.strip()
    expected = '''$EXPECTED_CONTENT'''.strip()
    # Check if the critical db.url line is present and correct
    db_line = [l for l in expected.splitlines() if 'db.url' in l][0]
    print('true' if db_line in actual else 'false')
except:
    print('false')
")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_match": $OUTPUT_MATCH,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "actual_content_preview": "$(echo "$ACTUAL_CONTENT" | head -n 1 | sed 's/"/\\"/g')",
    "expected_content_preview": "$(echo "$EXPECTED_CONTENT" | head -n 1 | sed 's/"/\\"/g')"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="