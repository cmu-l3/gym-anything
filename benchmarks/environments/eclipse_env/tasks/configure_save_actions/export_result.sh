#!/bin/bash
echo "=== Exporting Configure Save Actions Result ==="

source /workspace/scripts/task_utils.sh

# Paths
PROJECT_DIR="/home/ga/eclipse-workspace/LegacyCodebase"
PREFS_FILE="$PROJECT_DIR/.settings/org.eclipse.jdt.ui.prefs"
SOURCE_FILE="$PROJECT_DIR/src/main/java/com/legacy/MessyService.java"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if preferences file exists and capture content
PREFS_EXISTS="false"
PREFS_CONTENT=""
if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
    PREFS_CONTENT=$(cat "$PREFS_FILE")
fi

# Check if source file exists and capture content
SOURCE_EXISTS="false"
SOURCE_CONTENT=""
FILE_MODIFIED="false"
if [ -f "$SOURCE_FILE" ]; then
    SOURCE_EXISTS="true"
    SOURCE_CONTENT=$(cat "$SOURCE_FILE")
    
    # Check modification time
    MTIME=$(stat -c %Y "$SOURCE_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Escape content for JSON
PREFS_ESCAPED=$(echo "$PREFS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SOURCE_ESCAPED=$(echo "$SOURCE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "prefs_exists": $PREFS_EXISTS,
    "source_exists": $SOURCE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "prefs_content": $PREFS_ESCAPED,
    "source_content": $SOURCE_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="