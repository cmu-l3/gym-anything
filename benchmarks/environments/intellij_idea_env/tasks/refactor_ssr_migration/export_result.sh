#!/bin/bash
echo "=== Exporting Refactor SSR Migration Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-logging-system"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/logging/service/LogService.java"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file modification
FILE_MODIFIED="false"
FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 2. Check file content stats (grep counts)
LEGACY_COUNT=0
FLUENT_COUNT=0
CONTENT_ESCAPED='""'

if [ -f "$TARGET_FILE" ]; then
    LEGACY_COUNT=$(grep -c "LegacyLogger.log" "$TARGET_FILE" || echo "0")
    FLUENT_COUNT=$(grep -c "FluentLogger.at" "$TARGET_FILE" || echo "0")
    # Read content for detailed verification in python
    CONTENT_ESCAPED=$(cat "$TARGET_FILE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
fi

# 3. Compile Project to verify syntax
COMPILE_SUCCESS="false"
COMPILE_OUTPUT=""

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    echo "Compiling project..."
    cd "$PROJECT_DIR"
    # Run maven quietly
    COMPILE_OUTPUT_RAW=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        COMPILE_SUCCESS="true"
    fi
    
    # Escape output for JSON
    COMPILE_OUTPUT=$(echo "$COMPILE_OUTPUT_RAW" | tail -n 20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
fi

# 4. Construct JSON result
# Use a temp file to ensure atomic write and correct permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "legacy_count": $LEGACY_COUNT,
    "fluent_count": $FLUENT_COUNT,
    "compile_success": $COMPILE_SUCCESS,
    "compile_output": $COMPILE_OUTPUT,
    "file_content": $CONTENT_ESCAPED,
    "target_file_path": "$TARGET_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="