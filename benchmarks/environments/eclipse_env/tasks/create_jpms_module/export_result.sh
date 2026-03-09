#!/bin/bash
echo "=== Exporting JPMS Module Task Result ==="

source /workspace/scripts/task_utils.sh

# Project details
PROJECT_DIR="/home/ga/eclipse-workspace/ModularApp"
MODULE_INFO="$PROJECT_DIR/src/module-info.java"
REPORT_FILE="/home/ga/module_report.txt"
COMPILE_CHECK_SCRIPT="/tmp/check_compile.sh"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Data Collection ---

# 1. Check module-info.java existence and content
MODULE_INFO_EXISTS="false"
MODULE_INFO_CONTENT=""
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$MODULE_INFO" ]; then
    MODULE_INFO_EXISTS="true"
    MODULE_INFO_CONTENT=$(cat "$MODULE_INFO")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$MODULE_INFO" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check compilation status
# We create a temporary script to run javac because we need to set up the environment
cat > "$COMPILE_CHECK_SCRIPT" << 'EOF'
#!/bin/bash
cd /home/ga/eclipse-workspace/ModularApp
rm -rf /tmp/bin_check
mkdir -p /tmp/bin_check

# Find all java files
SOURCES=$(find src -name "*.java")

if [ -z "$SOURCES" ]; then
    echo "NO_SOURCES"
    exit 1
fi

# Compile with Java 17
/usr/lib/jvm/java-17-openjdk-amd64/bin/javac -d /tmp/bin_check $SOURCES 2>&1
EOF

chmod +x "$COMPILE_CHECK_SCRIPT"
COMPILE_OUTPUT=$("$COMPILE_CHECK_SCRIPT")
COMPILE_EXIT_CODE=$?

if [ $COMPILE_EXIT_CODE -eq 0 ]; then
    COMPILE_SUCCESS="true"
else
    COMPILE_SUCCESS="false"
fi

# 3. Check report file
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# 4. Prepare JSON content (escape strings for JSON safety)
MODULE_INFO_ESCAPED=$(echo "$MODULE_INFO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
REPORT_ESCAPED=$(echo "$REPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
COMPILE_OUTPUT_ESCAPED=$(echo "$COMPILE_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "module_info_exists": $MODULE_INFO_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "module_info_content": $MODULE_INFO_ESCAPED,
    "compile_success": $COMPILE_SUCCESS,
    "compile_output": $COMPILE_OUTPUT_ESCAPED,
    "report_exists": $REPORT_EXISTS,
    "report_content": $REPORT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="