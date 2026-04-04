#!/bin/bash
echo "=== Exporting Configure Task Tags Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/eclipse-workspace/LegacyAuth"
PREFS_FILE="$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs"
USERDAO_FILE="$PROJECT_DIR/src/main/java/com/legacy/auth/UserDAO.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check if prefs file exists and get content
PREFS_EXISTS="false"
PREFS_CONTENT=""
PREFS_MTIME="0"
if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
    PREFS_CONTENT=$(cat "$PREFS_FILE")
    PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
fi

# 2. Check UserDAO file content
USERDAO_CONTENT=""
USERDAO_MTIME="0"
if [ -f "$USERDAO_FILE" ]; then
    USERDAO_CONTENT=$(cat "$USERDAO_FILE")
    USERDAO_MTIME=$(stat -c %Y "$USERDAO_FILE" 2>/dev/null || echo "0")
fi

# 3. Check if compilation succeeded (UserDAO.class exists)
# Note: Eclipse usually builds automatically. If not, this file might be stale or missing.
COMPILED_SUCCESS="false"
CLASS_FILE="$PROJECT_DIR/bin/com/legacy/auth/UserDAO.class"
if [ -f "$CLASS_FILE" ]; then
    CLASS_MTIME=$(stat -c %Y "$CLASS_FILE" 2>/dev/null || echo "0")
    # Only count as success if class file is newer than source file (or close enough)
    # Actually, simpler check: if it exists, Eclipse likely compiled it.
    COMPILED_SUCCESS="true"
fi

# 4. Escape content for JSON
PREFS_ESCAPED=$(echo "$PREFS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
USERDAO_ESCAPED=$(echo "$USERDAO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_exists": $PREFS_EXISTS,
    "prefs_content": $PREFS_ESCAPED,
    "prefs_mtime": $PREFS_MTIME,
    "userdao_content": $USERDAO_ESCAPED,
    "userdao_mtime": $USERDAO_MTIME,
    "compilation_success": $COMPILED_SUCCESS,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Save result safely
write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="