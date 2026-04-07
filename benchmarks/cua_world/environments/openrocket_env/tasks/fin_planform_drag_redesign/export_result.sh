#!/bin/bash
echo "=== Exporting fin planform redesign result ==="
source /workspace/scripts/task_utils.sh || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final.png
else
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
fi

ORK_FILE="/home/ga/Documents/rockets/simple_model_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/fin_redesign_report.txt"

ork_exists="false"
report_exists="false"
ork_mtime=0
report_size=0

if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null || echo "0")
fi

# Flexible report paths
for p in "$REPORT_FILE" "/home/ga/Documents/exports/report.txt" "/home/ga/Documents/fin_redesign_report.txt" "/home/ga/fin_redesign_report.txt"; do
    if [ -f "$p" ]; then
        report_exists="true"
        report_size=$(stat -c %s "$p" 2>/dev/null || echo "0")
        break
    fi
done

# Check if app was running
APP_RUNNING="false"
if pgrep -f "OpenRocket.jar" > /dev/null; then
    APP_RUNNING="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ork_exists": $ork_exists,
    "ork_mtime": $ork_mtime,
    "report_exists": $report_exists,
    "report_size": $report_size,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="