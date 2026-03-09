#!/bin/bash
echo "=== Exporting create_physical_security_plan results ==="

source /workspace/scripts/task_utils.sh

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check for expected output files
EDDX_PATH="/home/ga/Diagrams/security_plan.eddx"
PNG_PATH="/home/ga/Diagrams/security_plan.png"

# Check EDDX
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    
    # Verify it was created during the task
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    else
        EDDX_CREATED_DURING_TASK="false"
    fi
else
    EDDX_EXISTS="false"
    EDDX_SIZE="0"
    EDDX_CREATED_DURING_TASK="false"
fi

# Check PNG
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    else
        PNG_CREATED_DURING_TASK="false"
    fi
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_CREATED_DURING_TASK="false"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING_TASK,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="