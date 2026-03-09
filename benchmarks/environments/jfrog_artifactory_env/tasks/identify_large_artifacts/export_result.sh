#!/bin/bash
echo "=== Exporting Identify Large Artifacts Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/large_artifacts.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Output File
FILE_EXISTS="false"
FILE_CONTENT=""
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    CREATED_DURING_TASK="false"
fi

# 2. Define Ground Truth (Based on what we deployed in setup)
# We know exactly what we put there.
# Large: apache-tomcat-9.0.85.tar.gz
# Small: commons-lang3-3.14.0.jar, commons-io-2.15.1.jar

LARGE_FILES_JSON='["apache-tomcat-9.0.85.tar.gz"]'
SMALL_FILES_JSON='["commons-lang3-3.14.0.jar", "commons-io-2.15.1.jar"]'

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_content": $(echo "$FILE_CONTENT" | jq -R -s '.'),
    "ground_truth_large": $LARGE_FILES_JSON,
    "ground_truth_small": $SMALL_FILES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="