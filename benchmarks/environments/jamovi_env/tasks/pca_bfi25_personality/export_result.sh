#!/bin/bash
set -e
echo "=== Exporting PCA BFI-25 task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Path definitions
OMV_PATH="/home/ga/Documents/Jamovi/BFI25_PCA.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/pca_report.txt"

# 1. Check OMV file (Jamovi Project)
OMV_EXISTS=false
OMV_SIZE=0
OMV_MODIFIED_DURING_TASK=false

if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS=true
    OMV_SIZE=$(stat -c%s "$OMV_PATH")
    OMV_MTIME=$(stat -c%Y "$OMV_PATH")
    
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_MODIFIED_DURING_TASK=true
    fi
fi

# 2. Check Report File
REPORT_EXISTS=false
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=true
    # Read content, limit to 1KB to prevent massive dumps
    REPORT_CONTENT=$(head -c 1024 "$REPORT_PATH")
fi

# 3. Check App Status
APP_RUNNING=false
if pgrep -f "org.jamovi.jamovi" > /dev/null || pgrep -f "jamovi" > /dev/null; then
    APP_RUNNING=true
fi

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_size_bytes": $OMV_SIZE,
    "omv_modified_during_task": $OMV_MODIFIED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"