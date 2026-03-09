#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JASP_FILE="/home/ga/Documents/JASP/Classifier_Comparison.jasp"
REPORT_FILE="/home/ga/Documents/JASP/model_performance.txt"

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check JASP File Status
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_MODIFIED="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE")
    if [ "$JASP_MTIME" -ge "$TASK_START" ]; then
        JASP_MODIFIED="true"
    fi
fi

# 3. Check Report File Status
REPORT_EXISTS="false"
REPORT_MODIFIED="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
    # Read content safely (limit size)
    REPORT_CONTENT=$(head -n 20 "$REPORT_FILE" | base64 -w 0)
fi

# 4. Check App Status
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_created_during_task": $JASP_MODIFIED,
    "jasp_file_size": $JASP_SIZE,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_created_during_task": $REPORT_MODIFIED,
    "report_content_b64": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Copy files for verifier to access via copy_from_env
# We copy the JASP file to /tmp/verifier_target.jasp to make it easy to pull
if [ "$JASP_EXISTS" == "true" ]; then
    cp "$JASP_FILE" /tmp/verifier_target.jasp
    chmod 644 /tmp/verifier_target.jasp
fi

# Move JSON to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"