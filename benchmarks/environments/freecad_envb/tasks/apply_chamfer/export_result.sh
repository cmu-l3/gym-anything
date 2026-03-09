#!/bin/bash
set -e
echo "=== Exporting apply_chamfer results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Define expected paths
OUTPUT_FCSTD="/home/ga/Documents/FreeCAD/chamfered_blocks.FCStd"
OUTPUT_STEP="/home/ga/Documents/FreeCAD/chamfered_topbox.step"

# 3. Check FCStd Output
FCSTD_EXISTS="false"
FCSTD_CREATED_DURING="false"
FCSTD_SIZE="0"

if [ -f "$OUTPUT_FCSTD" ]; then
    FCSTD_EXISTS="true"
    FCSTD_SIZE=$(stat -c %s "$OUTPUT_FCSTD")
    FCSTD_MTIME=$(stat -c %Y "$OUTPUT_FCSTD")
    
    if [ "$FCSTD_MTIME" -gt "$TASK_START" ]; then
        FCSTD_CREATED_DURING="true"
    fi
fi

# 4. Check STEP Output
STEP_EXISTS="false"
STEP_CREATED_DURING="false"
STEP_SIZE="0"
STEP_VALID_HEADER="false"

if [ -f "$OUTPUT_STEP" ]; then
    STEP_EXISTS="true"
    STEP_SIZE=$(stat -c %s "$OUTPUT_STEP")
    STEP_MTIME=$(stat -c %Y "$OUTPUT_STEP")
    
    if [ "$STEP_MTIME" -gt "$TASK_START" ]; then
        STEP_CREATED_DURING="true"
    fi

    # Check for STEP header signature (ISO-10303-21)
    if head -n 5 "$OUTPUT_STEP" | grep -q "ISO-10303-21"; then
        STEP_VALID_HEADER="true"
    fi
fi

# 5. Check if App was running
APP_RUNNING="false"
if pgrep -f "freecad" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Take final screenshot
take_screenshot /tmp/task_final.png

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_created_during_task": $FCSTD_CREATED_DURING,
    "fcstd_size_bytes": $FCSTD_SIZE,
    "step_exists": $STEP_EXISTS,
    "step_created_during_task": $STEP_CREATED_DURING,
    "step_size_bytes": $STEP_SIZE,
    "step_valid_header": $STEP_VALID_HEADER,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 8. Save result to /tmp/task_result.json safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"