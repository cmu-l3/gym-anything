#!/bin/bash
echo "=== Exporting Undo/Redo Task Results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/undo-redo-app"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_end.png

# 2. Check for Output File
OUTPUT_FILE="$PROJECT_DIR/output.txt"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
OUTPUT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Read first 1kb of output
    OUTPUT_CONTENT=$(head -c 1024 "$OUTPUT_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Verify Source Files Existence & Timestamps
check_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "old"
        fi
    else
        echo "false"
    fi
}

CMD_PKG="$PROJECT_DIR/src/main/java/com/editor/command"
FILE_STATUS_COMMAND=$(check_file "$CMD_PKG/Command.java")
FILE_STATUS_INSERT=$(check_file "$CMD_PKG/InsertCommand.java")
FILE_STATUS_DELETE=$(check_file "$CMD_PKG/DeleteCommand.java")
FILE_STATUS_REPLACE=$(check_file "$CMD_PKG/ReplaceCommand.java")
FILE_STATUS_HISTORY=$(check_file "$CMD_PKG/CommandHistory.java")
FILE_STATUS_MAIN=$(check_file "$PROJECT_DIR/src/main/java/com/editor/Main.java")

# 4. Attempt to Compile (Independent Verification)
# We run a separate Maven compile to verify syntax even if the agent didn't run it
echo "Attempting independent compilation..."
cd "$PROJECT_DIR"
COMPILE_LOG="/tmp/verification_compile.log"
if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile > "$COMPILE_LOG" 2>&1; then
    COMPILATION_SUCCESS="true"
else
    COMPILATION_SUCCESS="false"
fi

# 5. Export JSON
# Use python for safe JSON formatting
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'output_exists': $OUTPUT_EXISTS,
    'output_created_during_task': $OUTPUT_CREATED_DURING_TASK,
    'output_content': '''$OUTPUT_CONTENT''',
    'compilation_success': $COMPILATION_SUCCESS,
    'files': {
        'Command.java': '$FILE_STATUS_COMMAND',
        'InsertCommand.java': '$FILE_STATUS_INSERT',
        'DeleteCommand.java': '$FILE_STATUS_DELETE',
        'ReplaceCommand.java': '$FILE_STATUS_REPLACE',
        'CommandHistory.java': '$FILE_STATUS_HISTORY',
        'Main.java': '$FILE_STATUS_MAIN'
    },
    'screenshot_path': '/tmp/task_end.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"