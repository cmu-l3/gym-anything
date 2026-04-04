#!/bin/bash
echo "=== Exporting Inequality Analysis Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define expected paths
REPORT_PATH="/home/ga/Documents/gretl_output/inequality_report.txt"
PLOT_PATH="/home/ga/Documents/gretl_output/lorenz_income.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. analyze Report File
REPORT_EXISTS="false"
REPORT_CREATED="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Check if modified after start
    MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED="true"
    fi
    # Read content for JSON export (limit size)
    REPORT_CONTENT=$(head -n 20 "$REPORT_PATH" | base64 -w 0)
fi

# 4. Analyze Plot File
PLOT_EXISTS="false"
PLOT_CREATED="false"
PLOT_IS_IMAGE="false"
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED="true"
    fi
    # Verify it is a PNG
    if file "$PLOT_PATH" | grep -qi "PNG image data"; then
        PLOT_IS_IMAGE="true"
    fi
fi

# 5. Check if Gretl is still running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED,
    "report_content_b64": "$REPORT_CONTENT",
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED,
    "plot_valid_png": $PLOT_IS_IMAGE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"