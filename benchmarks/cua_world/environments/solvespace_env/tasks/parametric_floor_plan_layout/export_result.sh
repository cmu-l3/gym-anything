#!/bin/bash
echo "=== Exporting parametric_floor_plan_layout result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_FILE="/home/ga/Documents/SolveSpace/l_shape_floor_plan.slvs"
EXPORT_JSON="/tmp/task_result.json"
EXPORT_SLVS="/tmp/l_shape_floor_plan.slvs"

# Variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
APP_RUNNING="false"

# Check if application is running
if is_solvespace_running; then
    APP_RUNNING="true"
fi

# Check file existence and timestamps
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy the SLVS file to /tmp so the verifier can easily copy_from_env it
    cp "$OUTPUT_FILE" "$EXPORT_SLVS" 2>/dev/null || sudo cp "$OUTPUT_FILE" "$EXPORT_SLVS"
    chmod 666 "$EXPORT_SLVS" 2>/dev/null || sudo chmod 666 "$EXPORT_SLVS" 2>/dev/null || true
else
    # Create empty dummy file just so copy_from_env doesn't crash completely
    touch "$EXPORT_SLVS"
    chmod 666 "$EXPORT_SLVS"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f "$EXPORT_JSON" 2>/dev/null || sudo rm -f "$EXPORT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$EXPORT_JSON" 2>/dev/null || sudo cp "$TEMP_JSON" "$EXPORT_JSON"
chmod 666 "$EXPORT_JSON" 2>/dev/null || sudo chmod 666 "$EXPORT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to $EXPORT_JSON"
cat "$EXPORT_JSON"
echo "=== Export complete ==="