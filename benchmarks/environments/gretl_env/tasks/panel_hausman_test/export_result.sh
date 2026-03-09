#!/bin/bash
echo "=== Exporting Panel Hausman Test results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_PATH="$OUTPUT_DIR/panel_analysis.inp"
RESULT_PATH="$OUTPUT_DIR/panel_results.txt"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check Script File
SCRIPT_EXISTS="false"
SCRIPT_VALID="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Basic validation: contains 'panel' and 'hausman'
    if grep -iq "panel" "$SCRIPT_PATH" && grep -iq "hausman" "$SCRIPT_PATH"; then
        SCRIPT_VALID="true"
    fi
fi

# Check Result File
RESULT_EXISTS="false"
RESULT_SIZE="0"
RESULT_CREATED_DURING_TASK="false"

if [ -f "$RESULT_PATH" ]; then
    RESULT_EXISTS="true"
    RESULT_SIZE=$(stat -c%s "$RESULT_PATH")
    RESULT_MTIME=$(stat -c%Y "$RESULT_PATH")
    
    if [ "$RESULT_MTIME" -gt "$TASK_START" ]; then
        RESULT_CREATED_DURING_TASK="true"
    fi
fi

# Copy files to tmp for export/verification safety
cp "$SCRIPT_PATH" /tmp/panel_analysis.inp 2>/dev/null || true
cp "$RESULT_PATH" /tmp/panel_results.txt 2>/dev/null || true
chmod 644 /tmp/panel_analysis.inp /tmp/panel_results.txt 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_valid": $SCRIPT_VALID,
    "result_exists": $RESULT_EXISTS,
    "result_size": $RESULT_SIZE,
    "result_created_during_task": $RESULT_CREATED_DURING_TASK,
    "script_path": "/tmp/panel_analysis.inp",
    "result_path": "/tmp/panel_results.txt"
}
EOF

# Move result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="