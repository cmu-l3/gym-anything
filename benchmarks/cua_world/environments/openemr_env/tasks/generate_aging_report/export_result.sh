#!/bin/bash
# Export script for Generate Aging Report Task

echo "=== Exporting Aging Report Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    FINAL_SCREENSHOT_SIZE=0
fi

# Get current Firefox window title (may indicate current page)
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Current window title: $WINDOW_TITLE"

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null 2>&1; then
    FIREFOX_RUNNING="true"
    echo "Firefox is running"
else
    echo "WARNING: Firefox is not running"
fi

# Try to get current URL from Firefox (this may not work reliably)
# We'll rely more on screenshot analysis
CURRENT_URL=""
# Firefox doesn't easily expose current URL via command line

# Check database log for report access activity
echo "Checking database for report activity..."
INITIAL_LOG_COUNT=$(cat /tmp/initial_report_log_count.txt 2>/dev/null || echo "0")
CURRENT_LOG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM log WHERE event LIKE '%report%' OR comments LIKE '%report%'" 2>/dev/null || echo "0")

echo "Report log entries: initial=$INITIAL_LOG_COUNT, current=$CURRENT_LOG_COUNT"

# Check for recent report-related log entries
RECENT_REPORT_LOGS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "
SELECT date, event, comments 
FROM log 
WHERE (event LIKE '%report%' OR comments LIKE '%report%' OR comments LIKE '%billing%' OR comments LIKE '%collection%')
AND UNIX_TIMESTAMP(date) > $TASK_START
ORDER BY date DESC 
LIMIT 5" 2>/dev/null || echo "")

if [ -n "$RECENT_REPORT_LOGS" ]; then
    echo "Recent report activity detected:"
    echo "$RECENT_REPORT_LOGS"
    REPORT_ACTIVITY_DETECTED="true"
else
    echo "No recent report activity in logs"
    REPORT_ACTIVITY_DETECTED="false"
fi

# Check window title for report indicators
TITLE_INDICATES_REPORT="false"
TITLE_LOWER=$(echo "$WINDOW_TITLE" | tr '[:upper:]' '[:lower:]')
if echo "$TITLE_LOWER" | grep -qE "(report|billing|collection|aging|receivable)"; then
    TITLE_INDICATES_REPORT="true"
    echo "Window title suggests report view"
fi

# Check if user navigated past login page
PAST_LOGIN_PAGE="false"
if ! echo "$TITLE_LOWER" | grep -qE "(login|sign in)"; then
    PAST_LOGIN_PAGE="true"
fi
# Additional check - OpenEMR login page typically has specific title
if echo "$TITLE_LOWER" | grep -qE "openemr" && ! echo "$TITLE_LOWER" | grep -qE "login"; then
    PAST_LOGIN_PAGE="true"
fi

# Escape window title for JSON
WINDOW_TITLE_ESCAPED=$(echo "$WINDOW_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/aging_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $FINAL_SCREENSHOT_SIZE,
    "window_title": "$WINDOW_TITLE_ESCAPED",
    "title_indicates_report": $TITLE_INDICATES_REPORT,
    "past_login_page": $PAST_LOGIN_PAGE,
    "initial_report_log_count": $INITIAL_LOG_COUNT,
    "current_report_log_count": $CURRENT_LOG_COUNT,
    "report_activity_detected": $REPORT_ACTIVITY_DETECTED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/aging_report_result.json 2>/dev/null || sudo rm -f /tmp/aging_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aging_report_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/aging_report_result.json
chmod 666 /tmp/aging_report_result.json 2>/dev/null || sudo chmod 666 /tmp/aging_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy screenshots to accessible locations
cp /tmp/task_initial_state.png /tmp/initial_screenshot.png 2>/dev/null || true
cp /tmp/task_final_state.png /tmp/final_screenshot.png 2>/dev/null || true
chmod 666 /tmp/initial_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

echo ""
echo "Result JSON:"
cat /tmp/aging_report_result.json
echo ""
echo "=== Export Complete ==="