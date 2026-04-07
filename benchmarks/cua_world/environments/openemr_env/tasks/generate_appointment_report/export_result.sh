#!/bin/bash
# Export script for Generate Appointment Report task

echo "=== Exporting Generate Appointment Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png
if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    FINAL_SCREENSHOT_SIZE="0"
    SCREENSHOT_EXISTS="false"
    echo "WARNING: Could not capture final screenshot"
fi

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
    echo "Firefox is still running"
else
    echo "WARNING: Firefox is not running"
fi

# Get current window title (may indicate what page we're on)
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Active window title: $WINDOW_TITLE"

# Check for any exported report files in common locations
REPORT_FILE_FOUND="false"
REPORT_FILE_PATH=""

# Check common download/export locations
POSSIBLE_REPORT_PATHS=(
    "/home/ga/Downloads/*.csv"
    "/home/ga/Downloads/*.pdf"
    "/home/ga/Downloads/*.html"
    "/home/ga/Documents/*.csv"
    "/home/ga/Documents/*.pdf"
    "/tmp/*.csv"
    "/tmp/*.pdf"
)

for pattern in "${POSSIBLE_REPORT_PATHS[@]}"; do
    # Find files modified after task start
    FOUND_FILE=$(find $(dirname "$pattern") -name "$(basename "$pattern")" -newermt "@$TASK_START" 2>/dev/null | head -1)
    if [ -n "$FOUND_FILE" ]; then
        REPORT_FILE_FOUND="true"
        REPORT_FILE_PATH="$FOUND_FILE"
        echo "Found exported report file: $REPORT_FILE_PATH"
        break
    fi
done

# Get date info for verification
TODAY_DATE=$(cat /tmp/task_today_date.txt 2>/dev/null || date +%Y-%m-%d)
MONTH_START=$(cat /tmp/task_month_start.txt 2>/dev/null || date -d "$(date +%Y-%m-01)" +%Y-%m-%d)

# Check URL of Firefox (if possible via window title or other means)
# The window title often contains the page title
APPEARS_ON_REPORTS="false"
if echo "$WINDOW_TITLE" | grep -qi "report"; then
    APPEARS_ON_REPORTS="true"
    echo "Window title suggests reports page"
fi

# Escape window title for JSON
WINDOW_TITLE_ESCAPED=$(echo "$WINDOW_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 200)
REPORT_FILE_PATH_ESCAPED=$(echo "$REPORT_FILE_PATH" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/report_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $FINAL_SCREENSHOT_SIZE,
    "window_title": "$WINDOW_TITLE_ESCAPED",
    "appears_on_reports_page": $APPEARS_ON_REPORTS,
    "report_file_exported": $REPORT_FILE_FOUND,
    "report_file_path": "$REPORT_FILE_PATH_ESCAPED",
    "expected_date_range": {
        "from": "$MONTH_START",
        "to": "$TODAY_DATE"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/generate_report_result.json 2>/dev/null || sudo rm -f /tmp/generate_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/generate_report_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/generate_report_result.json
chmod 666 /tmp/generate_report_result.json 2>/dev/null || sudo chmod 666 /tmp/generate_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/generate_report_result.json"
cat /tmp/generate_report_result.json
echo ""
echo "=== Export Complete ==="