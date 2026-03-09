#!/bin/bash
echo "=== Exporting refactor_rename_class result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/refactor-demo"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check for new class file
OLD_FILE="$PROJECT_DIR/src/main/java/com/example/demo/OldClassName.java"
NEW_FILE="$PROJECT_DIR/src/main/java/com/example/demo/NewClassName.java"
MAIN_FILE="$PROJECT_DIR/src/main/java/com/example/demo/Main.java"

OLD_FILE_EXISTS="false"
NEW_FILE_EXISTS="false"
MAIN_UPDATED="false"
BUILD_SUCCESS="false"

NEW_CLASS_CONTENT=""
MAIN_CONTENT=""

if [ -f "$OLD_FILE" ]; then
    OLD_FILE_EXISTS="true"
fi

if [ -f "$NEW_FILE" ]; then
    NEW_FILE_EXISTS="true"
    NEW_CLASS_CONTENT=$(cat "$NEW_FILE" 2>/dev/null)
fi

if [ -f "$MAIN_FILE" ]; then
    MAIN_CONTENT=$(cat "$MAIN_FILE" 2>/dev/null)
    # Check if Main.java references NewClassName instead of OldClassName
    if echo "$MAIN_CONTENT" | grep -q "NewClassName" && ! echo "$MAIN_CONTENT" | grep -q "OldClassName"; then
        MAIN_UPDATED="true"
    fi
fi

# Check if agent successfully built the project (DO NOT run build ourselves!)
# The agent should have triggered the build through Eclipse - we only verify the result
if [ -f "$PROJECT_DIR/target/classes/com/example/demo/NewClassName.class" ]; then
    BUILD_SUCCESS="true"
fi

# Alternative: check for Main.class if refactoring was done correctly
if [ -f "$PROJECT_DIR/target/classes/com/example/demo/Main.class" ]; then
    BUILD_SUCCESS="true"
fi

# Escape content for JSON
NEW_CLASS_ESCAPED=$(echo "$NEW_CLASS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MAIN_ESCAPED=$(echo "$MAIN_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "old_file_exists": $OLD_FILE_EXISTS,
    "new_file_exists": $NEW_FILE_EXISTS,
    "main_updated": $MAIN_UPDATED,
    "build_success": $BUILD_SUCCESS,
    "new_class_content": $NEW_CLASS_ESCAPED,
    "main_content": $MAIN_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
