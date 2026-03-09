#!/bin/bash
echo "=== Exporting STRIDE Threat Model results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Documents"
EDDX_FILE="$OUTPUT_DIR/threat_model.eddx"
PNG_FILE="$OUTPUT_DIR/threat_model.png"

# Check EDDX file
if [ -f "$EDDX_FILE" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_FILE" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_FILE" 2>/dev/null || echo "0")
    
    # Verify file was created/modified DURING the task
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_VALID_TIME="true"
    else
        EDDX_VALID_TIME="false"
    fi
else
    EDDX_EXISTS="false"
    EDDX_SIZE="0"
    EDDX_VALID_TIME="false"
fi

# Check PNG file
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_FILE" 2>/dev/null || echo "0")
    
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_VALID_TIME="true"
    else
        PNG_VALID_TIME="false"
    fi
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_VALID_TIME="false"
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "EdrawMax" > /dev/null && echo "true" || echo "false")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size": $EDDX_SIZE,
    "eddx_valid_time": $EDDX_VALID_TIME,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_valid_time": $PNG_VALID_TIME,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to standard result location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="