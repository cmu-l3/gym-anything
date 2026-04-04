#!/bin/bash
set -e
echo "=== Exporting Jitsi URL Param Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
URL_FILE="/home/ga/meeting_url.txt"
REPORT_FILE="/home/ga/meeting_config_report.txt"
SCREENSHOT_FILE="/home/ga/meeting_configured.png"

# Check URL file
URL_FILE_EXISTS="false"
URL_FILE_SIZE="0"
if [ -f "$URL_FILE" ]; then
    URL_FILE_EXISTS="true"
    URL_FILE_SIZE=$(stat -c %s "$URL_FILE")
fi

# Check Report file
REPORT_FILE_EXISTS="false"
REPORT_FILE_SIZE="0"
if [ -f "$REPORT_FILE" ]; then
    REPORT_FILE_EXISTS="true"
    REPORT_FILE_SIZE=$(stat -c %s "$REPORT_FILE")
fi

# Check Agent Screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_FRESH="false"
if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    # Check if modified after task start
    F_MTIME=$(stat -c %Y "$SCREENSHOT_FILE")
    if [ "$F_MTIME" -ge "$TASK_START" ]; then
        SCREENSHOT_FRESH="true"
    fi
fi

# Check if Firefox is still running
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take system final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "url_file_exists": $URL_FILE_EXISTS,
    "url_file_size": $URL_FILE_SIZE,
    "report_file_exists": $REPORT_FILE_EXISTS,
    "report_file_size": $REPORT_FILE_SIZE,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_is_fresh": $SCREENSHOT_FRESH,
    "firefox_running": $FIREFOX_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="