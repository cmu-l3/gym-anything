#!/bin/bash
echo "=== Exporting Piecewise Spline Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define output paths
REGRESSION_OUTPUT="/home/ga/Documents/gretl_output/spline_regression.txt"
SLOPE_OUTPUT="/home/ga/Documents/gretl_output/high_income_slope.txt"

# Check file existence and timestamps
REG_EXISTS="false"
REG_CREATED_DURING="false"
if [ -f "$REGRESSION_OUTPUT" ]; then
    REG_EXISTS="true"
    REG_MTIME=$(stat -c %Y "$REGRESSION_OUTPUT" 2>/dev/null || echo "0")
    if [ "$REG_MTIME" -gt "$TASK_START" ]; then
        REG_CREATED_DURING="true"
    fi
fi

SLOPE_EXISTS="false"
SLOPE_CREATED_DURING="false"
if [ -f "$SLOPE_OUTPUT" ]; then
    SLOPE_EXISTS="true"
    SLOPE_MTIME=$(stat -c %Y "$SLOPE_OUTPUT" 2>/dev/null || echo "0")
    if [ "$SLOPE_MTIME" -gt "$TASK_START" ]; then
        SLOPE_CREATED_DURING="true"
    fi
fi

# Check if Gretl is running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "regression_output_exists": $REG_EXISTS,
    "regression_created_during_task": $REG_CREATED_DURING,
    "slope_output_exists": $SLOPE_EXISTS,
    "slope_created_during_task": $SLOPE_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export Complete ==="