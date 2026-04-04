#!/bin/bash
echo "=== Exporting Refactoring Result ==="

source /workspace/scripts/task_utils.sh

# Paths
# The agent might work directly in Documents or import to workspace
# We check both, preferring workspace if it exists
DOCS_DIR="/home/ga/Documents/FlightSystem"
WS_DIR="/home/ga/eclipse-workspace/FlightSystem"

if [ -d "$WS_DIR" ]; then
    PROJECT_DIR="$WS_DIR"
    echo "Found project in workspace: $PROJECT_DIR"
else
    PROJECT_DIR="$DOCS_DIR"
    echo "Using project in documents: $PROJECT_DIR"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if files exist
SERVICE_FILE="$PROJECT_DIR/src/com/flysky/service/BookingService.java"
APP_FILE="$PROJECT_DIR/src/com/flysky/app/BookingApp.java"
NEW_CLASS_FILE="$PROJECT_DIR/src/com/flysky/service/SeatDetails.java"

SERVICE_EXISTS="false"
APP_EXISTS="false"
NEW_CLASS_EXISTS="false"
SERVICE_CONTENT=""
APP_CONTENT=""
NEW_CLASS_CONTENT=""

if [ -f "$SERVICE_FILE" ]; then 
    SERVICE_EXISTS="true"
    SERVICE_CONTENT=$(cat "$SERVICE_FILE")
fi

if [ -f "$APP_FILE" ]; then 
    APP_EXISTS="true"
    APP_CONTENT=$(cat "$APP_FILE")
fi

if [ -f "$NEW_CLASS_FILE" ]; then 
    NEW_CLASS_EXISTS="true"
    NEW_CLASS_CONTENT=$(cat "$NEW_CLASS_FILE")
fi

# 2. Check Compilation
# We try to compile the project manually to verify it's valid Java
# We need to include the source path to resolve references
COMPILE_SUCCESS="false"
COMPILE_LOG=""

if [ "$SERVICE_EXISTS" = "true" ] && [ "$APP_EXISTS" = "true" ]; then
    mkdir -p /tmp/compile_test
    # We compile BookingApp because it depends on everything else. 
    # If it compiles, the refactoring (including call site updates) is valid.
    if javac -d /tmp/compile_test -sourcepath "$PROJECT_DIR/src" "$APP_FILE" > /tmp/compile.log 2>&1; then
        COMPILE_SUCCESS="true"
        echo "Compilation successful"
    else
        COMPILE_SUCCESS="false"
        COMPILE_LOG=$(head -n 20 /tmp/compile.log)
        echo "Compilation failed"
    fi
    rm -rf /tmp/compile_test
fi

# 3. Check Timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED="false"

if [ -f "$SERVICE_FILE" ]; then
    MOD_TIME=$(stat -c %Y "$SERVICE_FILE")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILES_MODIFIED="true"
    fi
fi

# Escape content for JSON
S_ESC=$(echo "$SERVICE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
A_ESC=$(echo "$APP_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
N_ESC=$(echo "$NEW_CLASS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
LOG_ESC=$(echo "$COMPILE_LOG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "service_exists": $SERVICE_EXISTS,
    "app_exists": $APP_EXISTS,
    "new_class_exists": $NEW_CLASS_EXISTS,
    "compile_success": $COMPILE_SUCCESS,
    "files_modified": $FILES_MODIFIED,
    "service_content": $S_ESC,
    "app_content": $A_ESC,
    "new_class_content": $N_ESC,
    "compile_log": $LOG_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="