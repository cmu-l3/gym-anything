#!/bin/bash
echo "=== Exporting LDA Heart Disease Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
JASP_FILE="/home/ga/Documents/JASP/Heart_LDA.jasp"
REPORT_FILE="/home/ga/Documents/JASP/lda_report.txt"

# Check JASP File
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_CREATED_DURING="false"
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 1000) # Cap size
fi

# Check if App is running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_size": $JASP_SIZE,
    "jasp_created_during_task": $JASP_CREATED_DURING,
    "report_exists": $REPORT_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy JASP file to temp for verifier access (if it exists)
if [ "$JASP_EXISTS" == "true" ]; then
    cp "$JASP_FILE" /tmp/verification_file.jasp
    chmod 666 /tmp/verification_file.jasp
fi

echo "Export summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="