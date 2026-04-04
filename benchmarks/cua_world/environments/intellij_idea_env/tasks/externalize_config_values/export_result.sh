#!/bin/bash
echo "=== Exporting externalize_config_values result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/config-app"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if compile works
echo "Running mvn compile..."
cd "$PROJECT_DIR"
COMPILE_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>&1)
COMPILE_EXIT_CODE=$?
if [ $COMPILE_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
else
    BUILD_SUCCESS="false"
fi

# 2. Read config.properties
PROPERTIES_FILE="$PROJECT_DIR/src/main/resources/config.properties"
PROPERTIES_CONTENT=""
PROPERTIES_EXISTS="false"
PROPERTIES_CREATED_DURING_TASK="false"

if [ -f "$PROPERTIES_FILE" ]; then
    PROPERTIES_EXISTS="true"
    PROPERTIES_CONTENT=$(cat "$PROPERTIES_FILE")
    
    # Check timestamp
    PROP_MTIME=$(stat -c %Y "$PROPERTIES_FILE" 2>/dev/null || echo "0")
    if [ "$PROP_MTIME" -gt "$TASK_START" ]; then
        PROPERTIES_CREATED_DURING_TASK="true"
    fi
fi

# 3. Read Source Files
DB_SERVICE_CONTENT=""
API_CLIENT_CONTENT=""
FILE_PROC_CONTENT=""

if [ -f "$PROJECT_DIR/src/main/java/com/appworks/DatabaseService.java" ]; then
    DB_SERVICE_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/appworks/DatabaseService.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/appworks/ApiClient.java" ]; then
    API_CLIENT_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/appworks/ApiClient.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/appworks/FileProcessor.java" ]; then
    FILE_PROC_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/appworks/FileProcessor.java")
fi

# 4. Check for properties loader mechanism
# Look for any new Java files or usage of Properties class
LOADER_FOUND="false"
# Simple heuristic: check if any java file imports java.util.Properties or uses ResourceBundle
# or if a new java file was created
ALL_JAVA_FILES=$(find "$PROJECT_DIR/src/main/java" -name "*.java")
for file in $ALL_JAVA_FILES; do
    if grep -q "Properties\|ResourceBundle\|FileInputStream" "$file"; then
        LOADER_FOUND="true"
        break
    fi
done

# Escape content for JSON
ESC_PROP=$(echo "$PROPERTIES_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ESC_DB=$(echo "$DB_SERVICE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ESC_API=$(echo "$API_CLIENT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ESC_FILE=$(echo "$FILE_PROC_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ESC_COMPILE=$(echo "$COMPILE_OUTPUT" | tail -10 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "build_success": $BUILD_SUCCESS,
    "build_output": $ESC_COMPILE,
    "properties_exists": $PROPERTIES_EXISTS,
    "properties_created_during_task": $PROPERTIES_CREATED_DURING_TASK,
    "properties_content": $ESC_PROP,
    "db_service_content": $ESC_DB,
    "api_client_content": $ESC_API,
    "file_processor_content": $ESC_FILE,
    "loader_mechanism_found": $LOADER_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="