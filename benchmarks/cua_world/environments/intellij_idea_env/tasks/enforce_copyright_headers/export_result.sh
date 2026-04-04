#!/bin/bash
echo "=== Exporting enforce_copyright_headers result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-service"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check compilation status
# We compile to ensure the headers didn't break the code (e.g. inserted before package without comments)
echo "Compiling project..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>&1)
BUILD_EXIT_CODE=$?
if [ $BUILD_EXIT_CODE -eq 0 ]; then
    COMPILE_SUCCESS="true"
else
    COMPILE_SUCCESS="false"
fi

# 3. Read Java files to check for headers
# We'll export the content of a few key files for the verifier to check regexes against
FILE_CONTENT_MAP="{}"

# Helper to escape and add file content to JSON map
add_file_to_json() {
    local filepath="$1"
    local json_key="$2"
    if [ -f "$filepath" ]; then
        local content=$(cat "$filepath" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
        FILE_CONTENT_MAP=$(echo "$FILE_CONTENT_MAP" | python3 -c "import sys, json; data=json.load(sys.stdin); data['$json_key'] = $content; print(json.dumps(data))")
    fi
}

add_file_to_json "$PROJECT_DIR/src/main/java/com/example/inventory/InventoryApplication.java" "InventoryApplication.java"
add_file_to_json "$PROJECT_DIR/src/main/java/com/example/inventory/model/Product.java" "Product.java"
add_file_to_json "$PROJECT_DIR/src/main/java/com/example/inventory/service/InventoryService.java" "InventoryService.java"

# 4. Check for IntelliJ Copyright Configuration Persistence
# Look for .idea/copyright directory and profiles
COPYRIGHT_CONFIG_EXISTS="false"
COPYRIGHT_PROFILE_CONTENT=""

if [ -d "$PROJECT_DIR/.idea/copyright" ]; then
    COPYRIGHT_CONFIG_EXISTS="true"
    # Try to find a profile XML
    PROFILE_XML=$(find "$PROJECT_DIR/.idea/copyright" -name "*.xml" | head -1)
    if [ -n "$PROFILE_XML" ]; then
        COPYRIGHT_PROFILE_CONTENT=$(cat "$PROFILE_XML" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
    fi
fi

# 5. Get file timestamps to ensure they were modified
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED_COUNT=0
for f in $(find "$PROJECT_DIR/src/main/java" -name "*.java"); do
    MOD_TIME=$(stat -c %Y "$f")
    if [ "$MOD_TIME" -gt "$TASK_START_TIME" ]; then
        FILES_MODIFIED_COUNT=$((FILES_MODIFIED_COUNT + 1))
    fi
done

# 6. Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "compile_success": $COMPILE_SUCCESS,
    "copyright_config_exists": $COPYRIGHT_CONFIG_EXISTS,
    "copyright_profile_content": ${COPYRIGHT_PROFILE_CONTENT:-"null"},
    "file_contents": $FILE_CONTENT_MAP,
    "files_modified_count": $FILES_MODIFIED_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="