#!/bin/bash
echo "=== Exporting sem_path_exam_anxiety result ==="

# Record task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
JASP_FILE="/home/ga/Documents/JASP/Exam_Path_Model.jasp"
REPORT_FILE="/home/ga/Documents/JASP/Model_Fit_Report.txt"
EXPORT_JASP="/tmp/Exam_Path_Model.jasp"
EXPORT_REPORT="/tmp/Model_Fit_Report.txt"

# check files
JASP_EXISTS="false"
REPORT_EXISTS="false"
JASP_CREATED_DURING="false"
REPORT_CREATED_DURING="false"
JASP_SIZE=0

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
    MTIME=$(stat -c %Y "$JASP_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
    # Copy for verification
    cp "$JASP_FILE" "$EXPORT_JASP"
    chmod 644 "$EXPORT_JASP"
fi

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Copy for verification
    cp "$REPORT_FILE" "$EXPORT_REPORT"
    chmod 644 "$EXPORT_REPORT"
fi

# App status
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_exists": $JASP_EXISTS,
    "jasp_created_during_task": $JASP_CREATED_DURING,
    "jasp_size_bytes": $JASP_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="