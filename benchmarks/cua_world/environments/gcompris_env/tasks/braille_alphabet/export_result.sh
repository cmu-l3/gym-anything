#!/bin/bash
set -e
echo "=== Exporting Braille Alphabet task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if GCompris is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# 2. Check for progress data modification
# GCompris writes to an sqlite DB or config files in ~/.local/share/GCompris/
# We check if any file in that directory was modified AFTER task start
DATA_DIR="/home/ga/.local/share/GCompris"
PROGRESS_MODIFIED="false"
MODIFIED_FILES=""

if [ -d "$DATA_DIR" ]; then
    # Find files modified after start time
    # We use -newermt (newer modification time)
    # Using a reference file with start time is safer for find
    touch -d "@$TASK_START" /tmp/start_ref
    
    MODIFIED_COUNT=$(find "$DATA_DIR" -type f -newer /tmp/start_ref 2>/dev/null | wc -l)
    
    if [ "$MODIFIED_COUNT" -gt 0 ]; then
        PROGRESS_MODIFIED="true"
        MODIFIED_FILES=$(find "$DATA_DIR" -type f -newer /tmp/start_ref -printf "%f, " 2>/dev/null)
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "progress_data_modified": $PROGRESS_MODIFIED,
    "modified_files": "$MODIFIED_FILES",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="