#!/bin/bash
# Export script for Generate Day Sheet Financial Report Task

echo "=== Exporting Generate Day Sheet Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png
sleep 1

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_DATE=$(cat /tmp/task_date.txt 2>/dev/null || date +%Y-%m-%d)

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get initial counts
INITIAL_LOG_COUNT=$(cat /tmp/initial_log_count.txt 2>/dev/null || echo "0")
INITIAL_REPORT_ACTIVITY=$(cat /tmp/initial_report_activity.txt 2>/dev/null || echo "0")

# Get current audit log count
CURRENT_LOG_COUNT=$(openemr_query "SELECT COUNT(*) FROM log" 2>/dev/null || echo "0")
echo "Log entries: initial=$INITIAL_LOG_COUNT, current=$CURRENT_LOG_COUNT"

# Check for login activity (user authenticated)
LOGIN_DETECTED="false"
LOGIN_EVENTS=$(openemr_query "SELECT COUNT(*) FROM log WHERE event='login' AND date >= FROM_UNIXTIME($TASK_START)" 2>/dev/null || echo "0")
if [ "$LOGIN_EVENTS" -gt "0" ]; then
    LOGIN_DETECTED="true"
    echo "Login detected: $LOGIN_EVENTS events"
fi

# Check for report-related activity in logs
REPORT_ACTIVITY=$(openemr_query "SELECT COUNT(*) FROM log WHERE (event LIKE '%report%' OR comments LIKE '%report%' OR comments LIKE '%day%sheet%' OR comments LIKE '%daily%' OR event LIKE '%view%') AND date >= FROM_UNIXTIME($TASK_START)" 2>/dev/null || echo "0")
echo "Report-related activity: $REPORT_ACTIVITY events"

# Check for financial/billing navigation
FINANCIAL_ACTIVITY=$(openemr_query "SELECT COUNT(*) FROM log WHERE (comments LIKE '%financial%' OR comments LIKE '%billing%' OR comments LIKE '%fee%' OR event LIKE '%billing%') AND date >= FROM_UNIXTIME($TASK_START)" 2>/dev/null || echo "0")
echo "Financial/billing activity: $FINANCIAL_ACTIVITY events"

# Get recent log entries for debugging
echo ""
echo "=== Recent log entries during task ==="
RECENT_LOGS=$(openemr_query "SELECT event, comments, date FROM log WHERE date >= FROM_UNIXTIME($TASK_START) ORDER BY date DESC LIMIT 20" 2>/dev/null)
echo "$RECENT_LOGS"

# Check for any exported files (in case agent exported the report)
EXPORT_FILE_FOUND="false"
EXPORT_FILE_PATH=""
POSSIBLE_EXPORTS=(
    "/home/ga/Downloads/day_sheet*.csv"
    "/home/ga/Downloads/day_sheet*.pdf"
    "/home/ga/Downloads/*report*.csv"
    "/home/ga/Downloads/*report*.pdf"
    "/home/ga/Documents/*.csv"
    "/tmp/*.csv"
)

for pattern in "${POSSIBLE_EXPORTS[@]}"; do
    files=$(ls $pattern 2>/dev/null)
    if [ -n "$files" ]; then
        for f in $files; do
            # Check if file was created during task
            FILE_MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
                EXPORT_FILE_FOUND="true"
                EXPORT_FILE_PATH="$f"
                echo "Found exported file: $f"
                break 2
            fi
        done
    fi
done

# Determine if report was likely generated based on activity
REPORT_GENERATED="false"
if [ "$CURRENT_LOG_COUNT" -gt "$INITIAL_LOG_COUNT" ]; then
    # Activity occurred during task
    NEW_ENTRIES=$((CURRENT_LOG_COUNT - INITIAL_LOG_COUNT))
    echo "New log entries during task: $NEW_ENTRIES"
    
    if [ "$REPORT_ACTIVITY" -gt "0" ] || [ "$FINANCIAL_ACTIVITY" -gt "0" ]; then
        REPORT_GENERATED="true"
        echo "Report generation activity detected"
    fi
fi

# Check Firefox window title for report indication
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Current window title: $WINDOW_TITLE"

TITLE_INDICATES_REPORT="false"
if echo "$WINDOW_TITLE" | grep -qiE "(report|day.?sheet|daily|financial|billing)"; then
    TITLE_INDICATES_REPORT="true"
    echo "Window title suggests report is displayed"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/day_sheet_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_date": "$TASK_DATE",
    "initial_log_count": $INITIAL_LOG_COUNT,
    "current_log_count": $CURRENT_LOG_COUNT,
    "login_detected": $LOGIN_DETECTED,
    "report_activity_count": $REPORT_ACTIVITY,
    "financial_activity_count": $FINANCIAL_ACTIVITY,
    "report_generated": $REPORT_GENERATED,
    "export_file_found": $EXPORT_FILE_FOUND,
    "export_file_path": "$EXPORT_FILE_PATH",
    "window_title": "$(echo "$WINDOW_TITLE" | sed 's/"/\\"/g')",
    "title_indicates_report": $TITLE_INDICATES_REPORT,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "initial_screenshot_exists": $([ -f "/tmp/task_initial.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/day_sheet_result.json 2>/dev/null || sudo rm -f /tmp/day_sheet_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/day_sheet_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/day_sheet_result.json
chmod 666 /tmp/day_sheet_result.json 2>/dev/null || sudo chmod 666 /tmp/day_sheet_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/day_sheet_result.json"
cat /tmp/day_sheet_result.json

echo ""
echo "=== Export Complete ==="