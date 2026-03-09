#!/bin/bash
echo "=== Exporting customize_code_templates result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/BankSystem"
CLASS_FILE="$PROJECT_DIR/src/com/securebank/core/BankAccount.java"
PREFS_FILE="$WORKSPACE/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.eclipse.jdt.ui.prefs"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Class File Content & Metadata
CLASS_EXISTS="false"
CLASS_CONTENT=""
CLASS_CREATED_DURING_TASK="false"

if [ -f "$CLASS_FILE" ]; then
    CLASS_EXISTS="true"
    CLASS_CONTENT=$(cat "$CLASS_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$CLASS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CLASS_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Preferences File (to ensure templates were actually saved)
PREFS_EXISTS="false"
PREFS_CONTENT=""

if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
    PREFS_CONTENT=$(cat "$PREFS_FILE")
fi

# 3. Check Directory Structure (Package Correctness)
PACKAGE_EXISTS="false"
if [ -d "$PROJECT_DIR/src/com/securebank/core" ]; then
    PACKAGE_EXISTS="true"
fi

# Prepare JSON Export
# Use Python to safely JSON-escape strings
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import json
import os
import sys

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'class_exists': $CLASS_EXISTS,
    'class_created_during_task': $CLASS_CREATED_DURING_TASK,
    'package_exists': $PACKAGE_EXISTS,
    'prefs_exists': $PREFS_EXISTS,
    'screenshot_path': '/tmp/task_final.png'
}

# Read content safely
class_content = \"\"\"$CLASS_CONTENT\"\"\"
prefs_content = \"\"\"$PREFS_CONTENT\"\"\"

result['class_content'] = class_content
result['prefs_content'] = prefs_content

print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="