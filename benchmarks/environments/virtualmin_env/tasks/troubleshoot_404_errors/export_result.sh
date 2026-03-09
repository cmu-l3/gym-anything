#!/bin/bash
echo "=== Exporting task results ==="

# ---------------------------------------------------------------
# 1. Load Configuration & Helper Data
# ---------------------------------------------------------------
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Read target info saved during setup
EXPECTED_PATH=$(grep -oP '"expected_path": "\K[^"]+' /tmp/task_target_info.json)
REL_PATH=$(grep -oP '"rel_path": "\K[^"]+' /tmp/task_target_info.json)

# ---------------------------------------------------------------
# 2. Check File Existence & Properties
# ---------------------------------------------------------------
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
DIR_EXISTS="false"

# Check directory structure (Partial credit check)
EXPECTED_DIR=$(dirname "$EXPECTED_PATH")
if [ -d "$EXPECTED_DIR" ]; then
    DIR_EXISTS="true"
fi

if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ---------------------------------------------------------------
# 3. Capture Evidence
# ---------------------------------------------------------------
# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---------------------------------------------------------------
# 4. Generate JSON Result
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "dir_exists": $DIR_EXISTS,
    "expected_path": "$EXPECTED_PATH",
    "target_rel_path": "$REL_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="