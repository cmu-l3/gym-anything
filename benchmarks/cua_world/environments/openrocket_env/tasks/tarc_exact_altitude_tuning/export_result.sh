#!/bin/bash
echo "=== Exporting tarc_exact_altitude_tuning result ==="

# Source utilities
source /workspace/scripts/task_utils.sh || exit 1

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null | grep -o '[0-9]*' || echo "0")
ORK_PATH="/home/ga/Documents/rockets/tuned_altitude_rocket.ork"
REPORT_PATH="/home/ga/Documents/exports/ballast_tuning_report.txt"

# Check ORK file
ork_exists="false"
ork_mtime="0"
if [ -f "$ORK_PATH" ]; then
    ork_exists="true"
    ork_mtime=$(stat -c %Y "$ORK_PATH" 2>/dev/null || echo "0")
fi

# Check Report file
report_exists="false"
report_size="0"
if [ -f "$REPORT_PATH" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# Check if OpenRocket is still running
app_running="false"
if pgrep -f "OpenRocket.jar" > /dev/null; then
    app_running="true"
fi

# Create result payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_running": $app_running,
    "ork_exists": $ork_exists,
    "ork_mtime": $ork_mtime,
    "report_exists": $report_exists,
    "report_size": $report_size
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="