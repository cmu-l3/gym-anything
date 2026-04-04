#!/bin/bash
echo "=== Exporting refactor_inheritance_to_delegation result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/network-module"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/network/SecureDataTransmitter.java"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Status
FILE_EXISTS="false"
FILE_MODIFIED="false"
CONTENT=""
INITIAL_HASH=$(awk '{print $1}' /tmp/initial_file_hash.txt 2>/dev/null || echo "")
CURRENT_HASH=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    CONTENT=$(cat "$TARGET_FILE")
    CURRENT_HASH=$(md5sum "$TARGET_FILE" | awk '{print $1}')
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_MODIFIED="true"
    elif [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        # Content changed even if timestamp is weird
        FILE_MODIFIED="true"
    fi
fi

# 3. Attempt Compilation (Optional but good signal)
# We expect compilation MIGHT fail in App.java if the user didn't fix usages,
# but SecureDataTransmitter.java itself should compile if we isolate it.
# For this task, we mainly care about the structure of SecureDataTransmitter.
COMPILE_SUCCESS="unknown"
if [ "$FILE_EXISTS" = "true" ]; then
    # Try to compile just the target file and its dependency
    cd "$PROJECT_DIR"
    if javac -cp src/main/java src/main/java/com/network/SecureDataTransmitter.java src/main/java/com/network/LegacySocket.java > /dev/null 2>&1; then
        COMPILE_SUCCESS="true"
    else
        COMPILE_SUCCESS="false"
    fi
fi

# 4. Create Result JSON
# Use Python for safe JSON escaping of the code content
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os
import sys

content = \"\"\"$(cat "$TARGET_FILE" 2>/dev/null || echo "")\"\"\"

result = {
    'file_exists': $FILE_EXISTS,
    'file_modified': $FILE_MODIFIED,
    'compile_success': '$COMPILE_SUCCESS',
    'file_content': content,
    'screenshot_path': '/tmp/task_final.png',
    'task_start_time': $TASK_START_TIME,
    'timestamp': '$(date -Iseconds)'
}

print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="