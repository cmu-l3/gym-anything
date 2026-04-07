#!/bin/bash
# Export script for Record Smoking Status Change Task

echo "=== Exporting Smoking Status Change Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target patient
PATIENT_PID=6

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial status
INITIAL_STATUS=$(cat /tmp/initial_smoking_status.txt 2>/dev/null || echo "")
INITIAL_HISTORY=$(cat /tmp/initial_history_tobacco.txt 2>/dev/null || echo "")
INITIAL_MTIME=$(cat /tmp/initial_patient_mtime.txt 2>/dev/null || echo "0")

echo "Initial status: '$INITIAL_STATUS'"
echo "Task start: $TASK_START"

# Get current tobacco status from patient_data table
echo ""
echo "=== Querying current smoking status ==="
CURRENT_STATUS=$(openemr_query "SELECT tobacco FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
echo "Current tobacco status (patient_data): '$CURRENT_STATUS'"

# Get current modification timestamp
CURRENT_MTIME=$(openemr_query "SELECT UNIX_TIMESTAMP(date) FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current patient record modification time: $CURRENT_MTIME"

# Also check history_data table
CURRENT_HISTORY_TOBACCO=$(openemr_query "SELECT tobacco FROM history_data WHERE pid=$PATIENT_PID ORDER BY date DESC LIMIT 1" 2>/dev/null || echo "")
echo "Current tobacco status (history_data): '$CURRENT_HISTORY_TOBACCO'"

# Check for any recent history_data entries
RECENT_HISTORY=$(openemr_query "SELECT id, tobacco, date FROM history_data WHERE pid=$PATIENT_PID ORDER BY date DESC LIMIT 3" 2>/dev/null || echo "")
echo "Recent history entries:"
echo "$RECENT_HISTORY"

# Determine if status changed
STATUS_CHANGED="false"
INITIAL_LOWER=$(echo "$INITIAL_STATUS" | tr '[:upper:]' '[:lower:]')
CURRENT_LOWER=$(echo "$CURRENT_STATUS" | tr '[:upper:]' '[:lower:]')
CURRENT_HISTORY_LOWER=$(echo "$CURRENT_HISTORY_TOBACCO" | tr '[:upper:]' '[:lower:]')

if [ "$INITIAL_LOWER" != "$CURRENT_LOWER" ] && [ -n "$CURRENT_STATUS" ]; then
    STATUS_CHANGED="true"
    echo "Status changed in patient_data: '$INITIAL_STATUS' -> '$CURRENT_STATUS'"
fi

# Check if the new status indicates "former smoker"
IS_FORMER="false"
for value in "former" "ex-" "quit" "past" "8517006"; do
    if echo "$CURRENT_LOWER" | grep -qi "$value"; then
        IS_FORMER="true"
        break
    fi
    if echo "$CURRENT_HISTORY_LOWER" | grep -qi "$value"; then
        IS_FORMER="true"
        break
    fi
done
echo "Is former smoker status: $IS_FORMER"

# Check if record was modified during task
RECORD_MODIFIED="false"
if [ "$CURRENT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    RECORD_MODIFIED="true"
    echo "Patient record was modified during task"
else
    echo "Patient record modification time not updated"
fi

# Also check if history_data was modified
HISTORY_MODIFIED="false"
HISTORY_COUNT_BEFORE=$(openemr_query "SELECT COUNT(*) FROM history_data WHERE pid=$PATIENT_PID AND UNIX_TIMESTAMP(date) < $TASK_START" 2>/dev/null || echo "0")
HISTORY_COUNT_AFTER=$(openemr_query "SELECT COUNT(*) FROM history_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
if [ "$HISTORY_COUNT_AFTER" -gt "$HISTORY_COUNT_BEFORE" ]; then
    HISTORY_MODIFIED="true"
    echo "New history_data entry was created"
fi

# Verify we're looking at the right patient
PATIENT_VERIFY=$(openemr_query "SELECT fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
PATIENT_FNAME=$(echo "$PATIENT_VERIFY" | cut -f1)
PATIENT_LNAME=$(echo "$PATIENT_VERIFY" | cut -f2)

# Escape special characters for JSON
CURRENT_STATUS_ESCAPED=$(echo "$CURRENT_STATUS" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
INITIAL_STATUS_ESCAPED=$(echo "$INITIAL_STATUS" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
CURRENT_HISTORY_ESCAPED=$(echo "$CURRENT_HISTORY_TOBACCO" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/[[:space:]]*$//')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/smoking_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_fname": "$PATIENT_FNAME",
    "patient_lname": "$PATIENT_LNAME",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_smoking_status": "$INITIAL_STATUS_ESCAPED",
    "current_smoking_status": "$CURRENT_STATUS_ESCAPED",
    "current_history_tobacco": "$CURRENT_HISTORY_ESCAPED",
    "status_changed": $STATUS_CHANGED,
    "is_former_smoker_value": $IS_FORMER,
    "record_modified_during_task": $RECORD_MODIFIED,
    "history_modified_during_task": $HISTORY_MODIFIED,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/smoking_status_result.json 2>/dev/null || sudo rm -f /tmp/smoking_status_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/smoking_status_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/smoking_status_result.json
chmod 666 /tmp/smoking_status_result.json 2>/dev/null || sudo chmod 666 /tmp/smoking_status_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/smoking_status_result.json"
cat /tmp/smoking_status_result.json

echo ""
echo "=== Export Complete ==="