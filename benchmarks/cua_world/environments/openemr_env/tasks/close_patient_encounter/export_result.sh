#!/bin/bash
# Export script for Close Patient Encounter Task

echo "=== Exporting Close Patient Encounter Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Target patient and encounter details
PATIENT_PID=6
ENCOUNTER_DATE="2019-10-15"

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ENCOUNTER_ID=$(cat /tmp/target_encounter_id.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Target encounter ID: $ENCOUNTER_ID"

# Get initial encounter state (recorded at setup)
INITIAL_STATE=$(cat /tmp/initial_encounter_state.txt 2>/dev/null || echo "")
echo "Initial encounter state: $INITIAL_STATE"

# Query current encounter state
echo ""
echo "=== Querying current encounter state ==="
CURRENT_ENCOUNTER=$(openemr_query "SELECT id, pid, DATE(date) as encounter_date, reason, last_level_closed, last_level_billed FROM form_encounter WHERE pid=$PATIENT_PID AND DATE(date)='$ENCOUNTER_DATE' LIMIT 1" 2>/dev/null)
echo "Current encounter data: $CURRENT_ENCOUNTER"

# Parse encounter data
ENC_ID=""
ENC_PID=""
ENC_DATE=""
ENC_REASON=""
ENC_CLOSED=""
ENC_BILLED=""

if [ -n "$CURRENT_ENCOUNTER" ]; then
    ENC_ID=$(echo "$CURRENT_ENCOUNTER" | cut -f1)
    ENC_PID=$(echo "$CURRENT_ENCOUNTER" | cut -f2)
    ENC_DATE=$(echo "$CURRENT_ENCOUNTER" | cut -f3)
    ENC_REASON=$(echo "$CURRENT_ENCOUNTER" | cut -f4)
    ENC_CLOSED=$(echo "$CURRENT_ENCOUNTER" | cut -f5)
    ENC_BILLED=$(echo "$CURRENT_ENCOUNTER" | cut -f6)
    
    echo ""
    echo "Parsed encounter data:"
    echo "  ID: $ENC_ID"
    echo "  Patient PID: $ENC_PID"
    echo "  Date: $ENC_DATE"
    echo "  Reason: $ENC_REASON"
    echo "  Closed Level: $ENC_CLOSED"
    echo "  Billed Level: $ENC_BILLED"
fi

# Determine if encounter was closed
ENCOUNTER_FOUND="false"
ENCOUNTER_CLOSED="false"
if [ -n "$ENC_ID" ]; then
    ENCOUNTER_FOUND="true"
    # Check if last_level_closed > 0 (indicates encounter was closed)
    if [ -n "$ENC_CLOSED" ] && [ "$ENC_CLOSED" != "0" ] && [ "$ENC_CLOSED" != "NULL" ]; then
        ENCOUNTER_CLOSED="true"
        echo "Encounter is NOW CLOSED (last_level_closed = $ENC_CLOSED)"
    else
        echo "Encounter is still OPEN (last_level_closed = $ENC_CLOSED)"
    fi
fi

# Check for any forms that might have been signed/closed
echo ""
echo "=== Checking form signatures ==="
FORM_SIGNATURES=$(openemr_query "SELECT form_id, form_name, formdir FROM forms WHERE pid=$PATIENT_PID AND encounter=$ENC_ID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Forms for this encounter: $FORM_SIGNATURES"

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
fi
echo "Firefox running: $FIREFOX_RUNNING"

# Escape reason for JSON
ENC_REASON_ESCAPED=$(echo "$ENC_REASON" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/close_encounter_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "target_encounter_id": "$ENCOUNTER_ID",
    "encounter_date": "$ENCOUNTER_DATE",
    "encounter_found": $ENCOUNTER_FOUND,
    "encounter": {
        "id": "$ENC_ID",
        "pid": "$ENC_PID",
        "date": "$ENC_DATE",
        "reason": "$ENC_REASON_ESCAPED",
        "last_level_closed": "$ENC_CLOSED",
        "last_level_billed": "$ENC_BILLED"
    },
    "encounter_is_closed": $ENCOUNTER_CLOSED,
    "initial_state": "$INITIAL_STATE",
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/close_encounter_result.json 2>/dev/null || sudo rm -f /tmp/close_encounter_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/close_encounter_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/close_encounter_result.json
chmod 666 /tmp/close_encounter_result.json 2>/dev/null || sudo chmod 666 /tmp/close_encounter_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result JSON ==="
cat /tmp/close_encounter_result.json
echo ""
echo "=== Export Complete ==="