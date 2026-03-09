#!/bin/bash
echo "=== Exporting fix_encoding_and_eol result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/InternationalApp"
JAVA_FILE="$PROJECT_DIR/src/com/legacy/WindowsService.java"
PREFS_FILE="$PROJECT_DIR/.settings/org.eclipse.core.resources.prefs"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check for CRLF line endings
# grep -U $'\r' checks for carriage returns. If found, it's still CRLF (or mixed).
HAS_CRLF="false"
if [ -f "$JAVA_FILE" ]; then
    if grep -qU $'\r' "$JAVA_FILE"; then
        HAS_CRLF="true"
    fi
fi

# 2. Check Project Encoding Setting
# We look for encoding/<project>=UTF-8 in the preferences file
ENCODING_SETTING="unknown"
if [ -f "$PREFS_FILE" ]; then
    # Extract the encoding value
    ENCODING_SETTING=$(grep "encoding/<project>" "$PREFS_FILE" | cut -d'=' -f2 | tr -d '\n\r')
fi

# 3. Verify file content integrity (ensure they didn't just delete the files)
JAVA_FILE_EXISTS="false"
PROP_FILE_EXISTS="false"
JAVA_SIZE=0
PROP_SIZE=0

if [ -f "$JAVA_FILE" ]; then
    JAVA_FILE_EXISTS="true"
    JAVA_SIZE=$(stat -c%s "$JAVA_FILE")
fi

if [ -f "$PROJECT_DIR/src/messages_jp.properties" ]; then
    PROP_FILE_EXISTS="true"
    PROP_SIZE=$(stat -c%s "$PROJECT_DIR/src/messages_jp.properties")
fi

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "has_crlf": $HAS_CRLF,
    "encoding_setting": "$ENCODING_SETTING",
    "java_file_exists": $JAVA_FILE_EXISTS,
    "prop_file_exists": $PROP_FILE_EXISTS,
    "java_size": $JAVA_SIZE,
    "prop_size": $PROP_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="