#!/bin/bash
echo "=== Exporting Bayesian Linear Regression Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JASP_FILE="/home/ga/Documents/JASP/ExamAnxiety_BayesRegression.jasp"
REPORT_FILE="/home/ga/Documents/JASP/bayesian_regression_report.txt"

# 1. Check JASP File
JASP_EXISTS="false"
JASP_SIZE=0
JASP_CREATED_DURING="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Read content safely (limit size)
    REPORT_CONTENT=$(head -c 1024 "$REPORT_FILE" | base64 -w 0)
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 4. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "path": "$JASP_FILE",
        "size": $JASP_SIZE,
        "created_during_task": $JASP_CREATED_DURING
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_FILE",
        "created_during_task": $REPORT_CREATED_DURING,
        "content_base64": "$REPORT_CONTENT"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to safe location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# If JASP file exists, copy it to tmp for the verifier to access via copy_from_env
if [ "$JASP_EXISTS" == "true" ]; then
    cp "$JASP_FILE" /tmp/verification_output.jasp
    chmod 666 /tmp/verification_output.jasp
fi

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="