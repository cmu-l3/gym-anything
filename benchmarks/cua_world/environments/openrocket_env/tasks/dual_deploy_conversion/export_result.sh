#!/bin/bash
echo "=== Exporting dual_deploy_conversion result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ROCKET_FILE="/home/ga/Documents/rockets/simple_model_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/dual_deploy_conversion_report.txt"

# Take final screenshot for VLM context
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gather file metrics for the rocket ORK file
ORK_EXISTS="false"
ORK_MTIME="0"
CURRENT_HASH=""
if [ -f "$ROCKET_FILE" ]; then
    ORK_EXISTS="true"
    ORK_MTIME=$(stat -c %Y "$ROCKET_FILE" 2>/dev/null || echo "0")
    CURRENT_HASH=$(md5sum "$ROCKET_FILE" | awk '{print $1}')
fi

# Gather file metrics for the conversion report
REPORT_EXISTS="false"
REPORT_MTIME="0"
REPORT_SIZE="0"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
fi

ORIGINAL_HASH=$(cat /tmp/original_ork_hash.txt 2>/dev/null || echo "none")

# Check if application was running
APP_RUNNING=$(pgrep -f "OpenRocket.jar" > /dev/null && echo "true" || echo "false")

# Create JSON result payload safely with temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ork_exists": $ORK_EXISTS,
    "ork_mtime": $ORK_MTIME,
    "original_hash": "$ORIGINAL_HASH",
    "current_hash": "$CURRENT_HASH",
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "app_was_running": $APP_RUNNING
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="