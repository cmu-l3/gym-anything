#!/bin/bash
echo "=== Exporting generate_delegate_methods result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROJECT_DIR="/home/ga/eclipse-workspace/MessageServiceApp"
TARGET_FILE="$PROJECT_DIR/src/com/messaging/decorator/LoggingMessageService.java"

# 1. Check file modification
FILE_MODIFIED="false"
FILE_MTIME="0"
if [ -f "$TARGET_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 2. Check compilation (headless javac verify)
echo "Verifying compilation..."
mkdir -p "$PROJECT_DIR/bin_verify"
javac -d "$PROJECT_DIR/bin_verify" -sourcepath "$PROJECT_DIR/src" "$PROJECT_DIR/src/com/messaging/app/Main.java" 2> /tmp/compile_errors.txt
COMPILE_EXIT_CODE=$?

COMPILATION_SUCCESS="false"
if [ $COMPILE_EXIT_CODE -eq 0 ]; then
    COMPILATION_SUCCESS="true"
else
    echo "Compilation failed:"
    cat /tmp/compile_errors.txt
fi

# 3. Check Runtime Output (only if compiled)
RUNTIME_OUTPUT=""
if [ "$COMPILATION_SUCCESS" = "true" ]; then
    RUNTIME_OUTPUT=$(java -cp "$PROJECT_DIR/bin_verify" com.messaging.app.Main 2>&1)
fi

# 4. Capture File Content
TARGET_CONTENT=""
if [ -f "$TARGET_FILE" ]; then
    TARGET_CONTENT=$(cat "$TARGET_FILE")
fi

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "import json, sys; print(json.dumps({
    'file_modified': '$FILE_MODIFIED' == 'true',
    'file_mtime': $FILE_MTIME,
    'task_start': $TASK_START,
    'compilation_success': '$COMPILATION_SUCCESS' == 'true',
    'compile_errors': open('/tmp/compile_errors.txt').read() if $COMPILE_EXIT_CODE != 0 else '',
    'runtime_output': sys.stdin.read(),
    'target_content': open('$TARGET_FILE').read() if '$FILE_MODIFIED' == 'true' or '$FILE_MTIME' != '0' else ''
}))" << EOF > "$TEMP_JSON"
$RUNTIME_OUTPUT
EOF

write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export complete ==="