#!/bin/bash
# Export script for Generate Audit Log Report Task

echo "=== Exporting Audit Log Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Target patient
PATIENT_PID=2
PATIENT_NAME="Rosa Bayer"

# Get initial counts
INITIAL_LOG_COUNT=$(cat /tmp/initial_log_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_COUNT=$(cat /tmp/total_log_count.txt 2>/dev/null || echo "0")

# Get current log counts
CURRENT_LOG_COUNT=$(openemr_query "SELECT COUNT(*) FROM log WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM log" 2>/dev/null || echo "0")

echo "Log entry counts:"
echo "  Patient-specific: initial=$INITIAL_LOG_COUNT, current=$CURRENT_LOG_COUNT"
echo "  Total system: initial=$INITIAL_TOTAL_COUNT, current=$CURRENT_TOTAL_COUNT"

# Check for audit-related log entries (viewing audit logs creates log entries)
echo ""
echo "=== Checking for audit log access events ==="
AUDIT_ACCESS_EVENTS=$(openemr_query "SELECT id, date, event, user, comments FROM log WHERE event LIKE '%audit%' OR event LIKE '%report%' OR comments LIKE '%audit%' ORDER BY date DESC LIMIT 10" 2>/dev/null)
echo "Recent audit-related events:"
echo "$AUDIT_ACCESS_EVENTS"

# Check for recent log viewing activity
echo ""
echo "=== Checking for recent log viewing activity ==="
RECENT_LOG_VIEWS=$(openemr_query "SELECT id, date, event, user, patient_id, comments FROM log WHERE date >= DATE_SUB(NOW(), INTERVAL 1 HOUR) ORDER BY date DESC LIMIT 20" 2>/dev/null)
echo "Recent log entries (past hour):"
echo "$RECENT_LOG_VIEWS"

# Check if any log entries exist for the target patient
echo ""
echo "=== Log entries for patient Rosa Bayer (pid=$PATIENT_PID) ==="
PATIENT_LOG_ENTRIES=$(openemr_query "SELECT id, date, event, user, comments FROM log WHERE patient_id=$PATIENT_PID ORDER BY date DESC LIMIT 10" 2>/dev/null)
if [ -n "$PATIENT_LOG_ENTRIES" ]; then
    echo "$PATIENT_LOG_ENTRIES"
    PATIENT_HAS_LOGS="true"
else
    echo "No log entries found for patient"
    PATIENT_HAS_LOGS="false"
fi

# Get date range info
TODAY=$(cat /tmp/date_today.txt 2>/dev/null || date +%Y-%m-%d)
THIRTY_DAYS_AGO=$(cat /tmp/date_30_days_ago.txt 2>/dev/null || date -d "-30 days" +%Y-%m-%d)

# Check for log entries within date range
DATE_RANGE_COUNT=$(openemr_query "SELECT COUNT(*) FROM log WHERE patient_id=$PATIENT_PID AND date >= '$THIRTY_DAYS_AGO' AND date <= '$TODAY 23:59:59'" 2>/dev/null || echo "0")
echo "Log entries for patient in date range ($THIRTY_DAYS_AGO to $TODAY): $DATE_RANGE_COUNT"

# Check current page URL if possible (from Firefox)
CURRENT_URL=""
if [ -f /home/ga/.mozilla/firefox/*.default-release/sessionstore-backups/recovery.jsonlz4 ]; then
    echo "Session store exists (could check URL)"
fi

# Determine if audit log was likely accessed based on evidence
AUDIT_LOG_ACCESSED="false"
NEW_LOG_ENTRIES=$((CURRENT_TOTAL_COUNT - INITIAL_TOTAL_COUNT))

# If there are new log entries, the agent did something
if [ "$NEW_LOG_ENTRIES" -gt 0 ]; then
    echo "Agent created $NEW_LOG_ENTRIES new log entries during task"
fi

# Check for specific audit log viewing patterns
AUDIT_VIEW_PATTERN=$(openemr_query "SELECT COUNT(*) FROM log WHERE date >= FROM_UNIXTIME($TASK_START) AND (event LIKE '%view%' OR event LIKE '%report%' OR event LIKE '%query%' OR comments LIKE '%log%')" 2>/dev/null || echo "0")
if [ "$AUDIT_VIEW_PATTERN" -gt 0 ]; then
    AUDIT_LOG_ACCESSED="true"
    echo "Found $AUDIT_VIEW_PATTERN potential audit log access events"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "patient": {
        "pid": $PATIENT_PID,
        "name": "$PATIENT_NAME"
    },
    "log_counts": {
        "patient_initial": $INITIAL_LOG_COUNT,
        "patient_current": $CURRENT_LOG_COUNT,
        "total_initial": $INITIAL_TOTAL_COUNT,
        "total_current": $CURRENT_TOTAL_COUNT,
        "new_entries": $NEW_LOG_ENTRIES
    },
    "date_range": {
        "start": "$THIRTY_DAYS_AGO",
        "end": "$TODAY",
        "entries_in_range": $DATE_RANGE_COUNT
    },
    "patient_has_logs": $PATIENT_HAS_LOGS,
    "audit_log_accessed": $AUDIT_LOG_ACCESSED,
    "audit_view_events": $AUDIT_VIEW_PATTERN,
    "screenshot_final_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "screenshot_initial_exists": $([ -f /tmp/task_initial.png ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result with proper permissions
rm -f /tmp/audit_log_result.json 2>/dev/null || sudo rm -f /tmp/audit_log_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/audit_log_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/audit_log_result.json
chmod 666 /tmp/audit_log_result.json 2>/dev/null || sudo chmod 666 /tmp/audit_log_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/audit_log_result.json"
cat /tmp/audit_log_result.json

echo ""
echo "=== Export Complete ==="