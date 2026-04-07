#!/bin/bash
# Export script for Generate Patient Statement task

echo "=== Exporting Patient Statement Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# Target patient
PATIENT_PID=3
PATIENT_FNAME="Jayson"
PATIENT_LNAME="Fadel"

# Take final screenshot before any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# Get initial values
INITIAL_LOG_COUNT=$(cat /tmp/initial_log_count.txt 2>/dev/null || echo "0")
INITIAL_BILLING_COUNT=$(cat /tmp/initial_billing_count.txt 2>/dev/null || echo "0")
EXPECTED_CHARGES=$(cat /tmp/expected_total_charges.txt 2>/dev/null || echo "0")

# Query for activity logs created during task
echo "Checking activity logs..."
CURRENT_LOG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM log" 2>/dev/null || echo "0")

NEW_LOG_ENTRIES=$((CURRENT_LOG_COUNT - INITIAL_LOG_COUNT))
echo "New log entries: $NEW_LOG_ENTRIES"

# Check for patient-related activity in logs
PATIENT_ACCESS_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM log WHERE 
    date >= FROM_UNIXTIME($TASK_START) AND
    (patient_id = $PATIENT_PID OR 
     comments LIKE '%$PATIENT_PID%' OR 
     comments LIKE '%$PATIENT_LNAME%' OR
     comments LIKE '%patient%')" 2>/dev/null || echo "0")
echo "Patient access log entries: $PATIENT_ACCESS_COUNT"

# Check for billing/fees related activity
BILLING_ACCESS_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM log WHERE 
    date >= FROM_UNIXTIME($TASK_START) AND
    (event LIKE '%billing%' OR 
     event LIKE '%fee%' OR 
     event LIKE '%statement%' OR
     event LIKE '%ledger%' OR
     event LIKE '%payment%' OR
     menu_item_id LIKE '%fee%' OR
     menu_item_id LIKE '%billing%')" 2>/dev/null || echo "0")
echo "Billing access log entries: $BILLING_ACCESS_COUNT"

# Check for login activity
LOGIN_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM log WHERE 
    date >= FROM_UNIXTIME($TASK_START) AND
    event LIKE '%login%'" 2>/dev/null || echo "0")
echo "Login log entries: $LOGIN_COUNT"

# Get billing records for patient
BILLING_RECORDS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*), COALESCE(SUM(fee), 0) FROM billing WHERE pid = $PATIENT_PID AND activity = 1" 2>/dev/null)

BILLING_COUNT=$(echo "$BILLING_RECORDS" | cut -f1)
TOTAL_FEES=$(echo "$BILLING_RECORDS" | cut -f2)
echo "Patient billing records: $BILLING_COUNT, Total fees: \$$TOTAL_FEES"

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null 2>&1; then
    FIREFOX_RUNNING="true"
fi

# Get current Firefox window title for context
WINDOW_TITLE=""
if [ "$FIREFOX_RUNNING" = "true" ]; then
    WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
fi

# Check for any statement/report files created
STATEMENT_FILE_FOUND="false"
STATEMENT_FILE_PATH=""
for pattern in "/home/ga/Downloads/*.pdf" "/home/ga/Documents/*.pdf" "/tmp/*.pdf" "/home/ga/Downloads/*statement*" "/home/ga/Documents/*statement*"; do
    found_files=$(find $(dirname "$pattern") -name "$(basename "$pattern")" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$found_files" ]; then
        STATEMENT_FILE_FOUND="true"
        STATEMENT_FILE_PATH="$found_files"
        echo "Found statement file: $STATEMENT_FILE_PATH"
        break
    fi
done

# Determine if billing section was likely accessed based on logs
BILLING_ACCESSED="false"
if [ "$BILLING_ACCESS_COUNT" -gt 0 ]; then
    BILLING_ACCESSED="true"
fi

# Determine if correct patient was accessed
PATIENT_ACCESSED="false"
if [ "$PATIENT_ACCESS_COUNT" -gt 0 ]; then
    PATIENT_ACCESSED="true"
fi

# Determine if login was successful
LOGIN_DETECTED="false"
if [ "$LOGIN_COUNT" -gt 0 ] || [ "$NEW_LOG_ENTRIES" -gt 2 ]; then
    LOGIN_DETECTED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/patient_statement_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "patient": {
        "pid": $PATIENT_PID,
        "fname": "$PATIENT_FNAME",
        "lname": "$PATIENT_LNAME"
    },
    "billing_data": {
        "record_count": ${BILLING_COUNT:-0},
        "total_fees": "${TOTAL_FEES:-0}"
    },
    "activity_detection": {
        "login_detected": $LOGIN_DETECTED,
        "patient_accessed": $PATIENT_ACCESSED,
        "billing_accessed": $BILLING_ACCESSED,
        "new_log_entries": $NEW_LOG_ENTRIES,
        "patient_access_log_count": $PATIENT_ACCESS_COUNT,
        "billing_access_log_count": $BILLING_ACCESS_COUNT,
        "login_log_count": $LOGIN_COUNT
    },
    "output": {
        "statement_file_found": $STATEMENT_FILE_FOUND,
        "statement_file_path": "$STATEMENT_FILE_PATH",
        "screenshot_exists": $SCREENSHOT_EXISTS,
        "screenshot_size_bytes": $SCREENSHOT_SIZE,
        "screenshot_path": "/tmp/task_final_state.png"
    },
    "environment": {
        "firefox_running": $FIREFOX_RUNNING,
        "window_title": "$WINDOW_TITLE"
    }
}
EOF

# Save result JSON with proper permissions
rm -f /tmp/patient_statement_result.json 2>/dev/null || sudo rm -f /tmp/patient_statement_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/patient_statement_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/patient_statement_result.json
chmod 666 /tmp/patient_statement_result.json 2>/dev/null || sudo chmod 666 /tmp/patient_statement_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result Summary ==="
cat /tmp/patient_statement_result.json
echo ""
echo "=== Export Complete ==="