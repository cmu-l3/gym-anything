#!/bin/bash
echo "=== Exporting Wilcoxon Task Results ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check JASP Output File
JASP_FILE="/home/ga/Documents/JASP/Exam_Wilcoxon_Test.jasp"
JASP_EXISTS="false"
JASP_CREATED_DURING="false"
JASP_SIZE="0"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# 4. Check Text Report
REPORT_FILE="/home/ga/Documents/JASP/median_analysis_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Read first 500 chars safely for JSON embedding
    REPORT_CONTENT=$(head -c 500 "$REPORT_FILE" | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# 5. Check if JASP is running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 6. Copy files to /tmp for verifier access (permissions)
# We copy them to a staging area that verifier.py can definitely read via copy_from_env
if [ "$JASP_EXISTS" = "true" ]; then
    cp "$JASP_FILE" /tmp/submission.jasp
    chmod 644 /tmp/submission.jasp
fi
if [ "$REPORT_EXISTS" = "true" ]; then
    cp "$REPORT_FILE" /tmp/submission_report.txt
    chmod 644 /tmp/submission_report.txt
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_created_during_task": $JASP_CREATED_DURING,
    "jasp_file_size": $JASP_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_content": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="