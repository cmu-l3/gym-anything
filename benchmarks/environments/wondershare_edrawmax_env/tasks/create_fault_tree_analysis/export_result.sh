#!/bin/bash
echo "=== Exporting create_fault_tree_analysis results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check EDDX file
EDDX_PATH="/home/ga/Documents/fta_db_failure.eddx"
EDDX_EXISTS="false"
EDDX_SIZE="0"
EDDX_CREATED_DURING="false"

if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    
    if [ "$EDDX_MTIME" -ge "$TASK_START" ]; then
        EDDX_CREATED_DURING="true"
    fi
fi

# 4. Check PNG file
PNG_PATH="/home/ga/Documents/fta_db_failure.png"
PNG_EXISTS="false"
PNG_SIZE="0"
PNG_CREATED_DURING="false"

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    if [ "$PNG_MTIME" -ge "$TASK_START" ]; then
        PNG_CREATED_DURING="true"
    fi
fi

# 5. Check if app is still running
APP_RUNNING="false"
if is_edrawmax_running; then
    APP_RUNNING="true"
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size_bytes": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING,
    "png_exists": $PNG_EXISTS,
    "png_size_bytes": $PNG_SIZE,
    "png_created_during_task": $PNG_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="