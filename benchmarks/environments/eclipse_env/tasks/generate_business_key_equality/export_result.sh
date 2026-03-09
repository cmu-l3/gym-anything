#!/bin/bash
echo "=== Exporting generate_business_key_equality result ==="

source /workspace/scripts/task_utils.sh

# Paths
PROJECT_DIR="/home/ga/eclipse-workspace/InventorySystem"
JAVA_FILE="$PROJECT_DIR/src/main/java/com/store/model/Product.java"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
CONTENT=""

if [ -f "$JAVA_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$JAVA_FILE")
    FILE_MTIME=$(stat -c %Y "$JAVA_FILE")
    
    # Check if modified after start
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Read content
    CONTENT=$(cat "$JAVA_FILE")
fi

# 3. Check Compilation
# Run Maven compile to verify syntax is valid
echo "Running compilation check..."
cd "$PROJECT_DIR"
if run_maven "$PROJECT_DIR" "compile" "/tmp/mvn_compile.log"; then
    COMPILE_SUCCESS="true"
else
    COMPILE_SUCCESS="false"
fi

# 4. Prepare JSON Result
# Escape content for JSON safety
ESCAPED_CONTENT=$(echo "$CONTENT" | python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "compile_success": $COMPILE_SUCCESS,
    "file_content": $ESCAPED_CONTENT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to /tmp/task_result.json safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="