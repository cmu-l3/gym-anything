#!/bin/bash
echo "=== Exporting Externalize Strings i18n Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps and paths
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/eclipse-workspace/LibraryApp"
APP_DIR="$PROJECT_DIR/src/main/java/com/library/app"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if messages.properties exists
PROPS_FILE="$APP_DIR/messages.properties"
PROPS_EXISTS="false"
PROPS_CONTENT=""
PROPS_ENTRY_COUNT=0
PROPS_MTIME=0

if [ -f "$PROPS_FILE" ]; then
    PROPS_EXISTS="true"
    PROPS_CONTENT=$(cat "$PROPS_FILE")
    # Count non-empty lines that aren't comments
    PROPS_ENTRY_COUNT=$(grep -v "^#" "$PROPS_FILE" | grep -v "^$" | wc -l)
    PROPS_MTIME=$(stat -c %Y "$PROPS_FILE")
fi

# 2. Check if Messages.java exists
ACCESSOR_FILE="$APP_DIR/Messages.java"
ACCESSOR_EXISTS="false"
ACCESSOR_CONTENT=""

if [ -f "$ACCESSOR_FILE" ]; then
    ACCESSOR_EXISTS="true"
    ACCESSOR_CONTENT=$(cat "$ACCESSOR_FILE")
fi

# 3. Check LibraryApp.java for changes
TARGET_FILE="$APP_DIR/LibraryApp.java"
TARGET_CONTENT=""
ORIGINAL_HASH=$(cat /tmp/original_hash.txt 2>/dev/null || echo "")
CURRENT_HASH=""
FILE_MODIFIED="false"
GET_STRING_COUNT=0

if [ -f "$TARGET_FILE" ]; then
    TARGET_CONTENT=$(cat "$TARGET_FILE")
    CURRENT_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
    
    if [ "$CURRENT_HASH" != "$ORIGINAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Count occurrences of Messages.getString
    GET_STRING_COUNT=$(grep -o "Messages.getString" "$TARGET_FILE" | wc -l)
fi

# 4. Check if project compiles (look for class files or run maven)
BUILD_SUCCESS="false"
# Try a quick maven compile to verify
cd "$PROJECT_DIR"
if sudo -u ga mvn compile -q -DskipTests > /tmp/mvn_build.log 2>&1; then
    BUILD_SUCCESS="true"
fi

# Escape content for JSON safely
json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

PROPS_ESCAPED=$(echo "$PROPS_CONTENT" | json_escape)
ACCESSOR_ESCAPED=$(echo "$ACCESSOR_CONTENT" | json_escape)
TARGET_ESCAPED=$(echo "$TARGET_CONTENT" | json_escape)

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "properties_file_exists": $PROPS_EXISTS,
    "properties_entry_count": $PROPS_ENTRY_COUNT,
    "properties_mtime": $PROPS_MTIME,
    "accessor_file_exists": $ACCESSOR_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "get_string_count": $GET_STRING_COUNT,
    "build_success": $BUILD_SUCCESS,
    "properties_content": $PROPS_ESCAPED,
    "accessor_content": $ACCESSOR_ESCAPED,
    "target_content": $TARGET_ESCAPED
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"