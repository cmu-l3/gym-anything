#!/bin/bash
echo "=== Exporting ANCOVA Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
JASP_FILE="/home/ga/Documents/JASP/ExamAnxiety_ANCOVA.jasp"
REPORT_FILE="/home/ga/Documents/JASP/ancova_report.txt"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Verify JASP File
JASP_EXISTS="false"
JASP_SIZE=0
JASP_VALID_ZIP="false"
JASP_CREATED_DURING="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE")
    
    # Check creation time
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
    
    # Check if valid zip (JASP files are zips)
    if unzip -t "$JASP_FILE" > /dev/null 2>&1; then
        JASP_VALID_ZIP="true"
    fi
fi

# 3. Verify Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Read content (escape quotes for JSON)
    # Limit to first 2KB to avoid huge JSONs
    REPORT_CONTENT=$(head -c 2000 "$REPORT_FILE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="\"\""
fi

# 4. Check if JASP is running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "size": $JASP_SIZE,
        "valid_zip": $JASP_VALID_ZIP,
        "created_during_task": $JASP_CREATED_DURING
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "content": $REPORT_CONTENT,
        "created_during_task": $REPORT_CREATED_DURING
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json