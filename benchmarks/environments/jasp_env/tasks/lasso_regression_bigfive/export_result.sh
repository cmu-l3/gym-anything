#!/bin/bash
echo "=== Exporting Lasso Regression Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check JASP Project File
JASP_FILE="/home/ga/Documents/JASP/LassoRegressionBigFive.jasp"
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_CREATED_DURING_TASK="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check Report File
REPORT_FILE="/home/ga/Documents/JASP/lasso_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    # Read first 500 chars of report for quick verification context
    REPORT_CONTENT=$(head -c 500 "$REPORT_FILE" | sed 's/"/\\"/g' | tr '\n' ' ')
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 5. Check if JASP is still running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "path": "$JASP_FILE",
        "size_bytes": $JASP_SIZE,
        "created_during_task": $JASP_CREATED_DURING_TASK
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_FILE",
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content_snippet": "$REPORT_CONTENT"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move JSON to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"