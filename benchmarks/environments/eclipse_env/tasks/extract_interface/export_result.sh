#!/bin/bash
echo "=== Exporting Extract Interface results ==="

PROJECT_DIR="/home/ga/eclipse-workspace/ServiceApp"
SRC_BASE="$PROJECT_DIR/src/main/java/com/serviceapp"

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check compilation status
# We attempt to compile all Java files in the source tree.
# If refactoring was done correctly, this should succeed.
COMPILATION_OUTPUT=$(mktemp)
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
$JAVA_HOME/bin/javac -d "$PROJECT_DIR/bin" $(find "$SRC_BASE" -name "*.java") > "$COMPILATION_OUTPUT" 2>&1
COMPILE_EXIT_CODE=$?

if [ $COMPILE_EXIT_CODE -eq 0 ]; then
    COMPILES="true"
else
    COMPILES="false"
fi

# 3. Check for IUserService.java existence and content
INTERFACE_PATH="$SRC_BASE/service/IUserService.java"
INTERFACE_EXISTS="false"
INTERFACE_CONTENT=""

if [ -f "$INTERFACE_PATH" ]; then
    INTERFACE_EXISTS="true"
    INTERFACE_CONTENT=$(cat "$INTERFACE_PATH")
fi

# 4. Check modification times against task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED="false"

# Check if UserService.java was modified
USER_SERVICE_PATH="$SRC_BASE/service/UserService.java"
if [ -f "$USER_SERVICE_PATH" ]; then
    US_MTIME=$(stat -c %Y "$USER_SERVICE_PATH")
    if [ "$US_MTIME" -gt "$TASK_START" ]; then
        FILES_MODIFIED="true"
    fi
fi

# 5. Read file contents for verification
USER_SERVICE_CONTENT=$(cat "$USER_SERVICE_PATH" 2>/dev/null || echo "")
USER_CONTROLLER_CONTENT=$(cat "$SRC_BASE/controller/UserController.java" 2>/dev/null || echo "")
COMPILE_LOG=$(cat "$COMPILATION_OUTPUT")

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "compilation_success": $COMPILES,
    "compilation_log": $(echo "$COMPILE_LOG" | jq -R -s '.'),
    "interface_exists": $INTERFACE_EXISTS,
    "interface_content": $(echo "$INTERFACE_CONTENT" | jq -R -s '.'),
    "user_service_content": $(echo "$USER_SERVICE_CONTENT" | jq -R -s '.'),
    "user_controller_content": $(echo "$USER_CONTROLLER_CONTENT" | jq -R -s '.'),
    "files_modified": $FILES_MODIFIED
}
EOF

# Move to standard location with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

rm -f "$COMPILATION_OUTPUT"
echo "Results exported to /tmp/task_result.json"