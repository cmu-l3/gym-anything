#!/bin/bash
set -euo pipefail

echo "=== Exporting Atmospheric Extinction Results ==="

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

REPORT_FILE="/home/ga/AstroImages/measurements/extinction_report.txt"
DATA_CSV="/home/ga/AstroImages/measurements/photometry_results.csv"

# Check output state
REPORT_EXISTS="false"
REPORT_CONTENT=""
DATA_EXISTS="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Take first 10 lines, strip quotes to keep json valid
    REPORT_CONTENT=$(head -n 10 "$REPORT_FILE" | tr '"' "'")
fi

if [ -f "$DATA_CSV" ] || [ -f "/home/ga/AstroImages/measurements/photometry_results.xls" ] || [ -f "/home/ga/AstroImages/measurements/photometry_results.tbl" ]; then
    DATA_EXISTS="true"
else
    # Check if they saved it anywhere in measurements
    FOUND_DATA=$(find /home/ga/AstroImages/measurements/ -type f \( -name "*.csv" -o -name "*.xls" -o -name "*.tbl" \) | wc -l)
    if [ "$FOUND_DATA" -gt 0 ]; then
        DATA_EXISTS="true"
    fi
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "data_exists": $DATA_EXISTS,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Handle permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="