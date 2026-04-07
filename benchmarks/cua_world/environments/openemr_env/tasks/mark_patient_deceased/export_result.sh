#!/bin/bash
# Export script for Mark Patient as Deceased task
# Queries database and saves verification data to JSON

echo "=== Exporting Mark Patient as Deceased Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Configuration
PATIENT_PID=7
EXPECTED_DEATH_DATE="2024-03-15"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Get initial deceased status (recorded at task start)
INITIAL_DECEASED=$(cat /tmp/initial_deceased_status.txt 2>/dev/null || echo "NULL")
INITIAL_MOD_TIME=$(cat /tmp/initial_mod_time.txt 2>/dev/null || echo "0")

echo "Initial deceased status: $INITIAL_DECEASED"

# Query current patient data
echo ""
echo "=== Querying patient deceased status ==="
PATIENT_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pid, fname, lname, DOB, 
            IFNULL(deceased_date, 'NULL') as deceased_date, 
            IFNULL(deceased_reason, 'NULL') as deceased_reason,
            UNIX_TIMESTAMP(date) as mod_timestamp
     FROM patient_data 
     WHERE pid=$PATIENT_PID" 2>/dev/null)

echo "Patient data: $PATIENT_DATA"

# Parse patient data
PATIENT_FOUND="false"
CURRENT_DECEASED_DATE="NULL"
CURRENT_DECEASED_REASON="NULL"
CURRENT_MOD_TIME="0"
PATIENT_FNAME=""
PATIENT_LNAME=""

if [ -n "$PATIENT_DATA" ]; then
    PATIENT_FOUND="true"
    
    # Parse tab-separated values
    PATIENT_FNAME=$(echo "$PATIENT_DATA" | cut -f2)
    PATIENT_LNAME=$(echo "$PATIENT_DATA" | cut -f3)
    CURRENT_DECEASED_DATE=$(echo "$PATIENT_DATA" | cut -f5)
    CURRENT_DECEASED_REASON=$(echo "$PATIENT_DATA" | cut -f6)
    CURRENT_MOD_TIME=$(echo "$PATIENT_DATA" | cut -f7)
    
    echo ""
    echo "Parsed patient data:"
    echo "  Name: $PATIENT_FNAME $PATIENT_LNAME"
    echo "  Deceased Date: $CURRENT_DECEASED_DATE"
    echo "  Deceased Reason: $CURRENT_DECEASED_REASON"
    echo "  Modification Time: $CURRENT_MOD_TIME"
fi

# Determine if record was modified during task
RECORD_MODIFIED="false"
if [ "$CURRENT_MOD_TIME" -gt "$INITIAL_MOD_TIME" ] && [ "$CURRENT_MOD_TIME" -ge "$TASK_START" ]; then
    RECORD_MODIFIED="true"
    echo "Record was modified during task execution"
elif [ "$CURRENT_MOD_TIME" -gt "$INITIAL_MOD_TIME" ]; then
    RECORD_MODIFIED="true"
    echo "Record was modified (possibly during task)"
else
    echo "Record modification time unchanged"
fi

# Check if deceased date matches expected
DECEASED_DATE_CORRECT="false"
if [ "$CURRENT_DECEASED_DATE" != "NULL" ] && [ -n "$CURRENT_DECEASED_DATE" ]; then
    # Check if the date contains the expected date (handles various formats)
    if echo "$CURRENT_DECEASED_DATE" | grep -q "$EXPECTED_DEATH_DATE"; then
        DECEASED_DATE_CORRECT="true"
        echo "Deceased date matches expected: $EXPECTED_DEATH_DATE"
    else
        echo "Deceased date ($CURRENT_DECEASED_DATE) does not match expected ($EXPECTED_DEATH_DATE)"
    fi
else
    echo "Deceased date not set"
fi

# Check if status changed from initial
STATUS_CHANGED="false"
if [ "$INITIAL_DECEASED" = "NULL" ] || [ -z "$INITIAL_DECEASED" ]; then
    if [ "$CURRENT_DECEASED_DATE" != "NULL" ] && [ -n "$CURRENT_DECEASED_DATE" ]; then
        STATUS_CHANGED="true"
        echo "Patient status changed from active to deceased"
    fi
fi

# Escape special characters for JSON
CURRENT_DECEASED_REASON_ESCAPED=$(echo "$CURRENT_DECEASED_REASON" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/deceased_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_found": $PATIENT_FOUND,
    "patient_name": "$PATIENT_FNAME $PATIENT_LNAME",
    "initial_deceased_status": "$INITIAL_DECEASED",
    "current_deceased_date": "$CURRENT_DECEASED_DATE",
    "current_deceased_reason": "$CURRENT_DECEASED_REASON_ESCAPED",
    "expected_death_date": "$EXPECTED_DEATH_DATE",
    "deceased_date_correct": $DECEASED_DATE_CORRECT,
    "status_changed": $STATUS_CHANGED,
    "record_modified": $RECORD_MODIFIED,
    "initial_mod_time": $INITIAL_MOD_TIME,
    "current_mod_time": $CURRENT_MOD_TIME,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/mark_deceased_result.json 2>/dev/null || sudo rm -f /tmp/mark_deceased_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mark_deceased_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mark_deceased_result.json
chmod 666 /tmp/mark_deceased_result.json 2>/dev/null || sudo chmod 666 /tmp/mark_deceased_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/mark_deceased_result.json"
cat /tmp/mark_deceased_result.json

echo ""
echo "=== Export Complete ==="