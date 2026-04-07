#!/bin/bash
# Export script for Create Patient Encounter task
# Queries database and exports all verification data to JSON

echo "=== Exporting Create Patient Encounter Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Taking final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Target patient
PATIENT_PID=3

# Get initial state from setup
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count.txt 2>/dev/null || echo "0")
HIGHEST_INITIAL_ID=$(cat /tmp/highest_encounter_id.txt 2>/dev/null || echo "0")

# Get current encounter count for patient
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo ""
echo "Encounter count comparison:"
echo "  Initial count for patient: $INITIAL_ENCOUNTER_COUNT"
echo "  Current count for patient: $CURRENT_ENCOUNTER_COUNT"
echo "  Highest initial ID (global): $HIGHEST_INITIAL_ID"

# Query for ALL encounters for this patient (for debugging)
echo ""
echo "=== All encounters for patient PID=$PATIENT_PID ==="
openemr_query "SELECT id, date, reason, encounter FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null
echo ""

# Find NEW encounters (id > highest initial id AND for our patient)
NEW_ENCOUNTERS=$(openemr_query "SELECT id, pid, date, reason, encounter, pc_catid, facility_id, provider_id FROM form_encounter WHERE pid=$PATIENT_PID AND id > $HIGHEST_INITIAL_ID ORDER BY id DESC" 2>/dev/null)

# Get the most recent encounter for this patient
NEWEST_ENCOUNTER=$(openemr_query "SELECT id, pid, date, reason, encounter, pc_catid, facility_id, provider_id FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse newest encounter data
ENCOUNTER_FOUND="false"
ENCOUNTER_ID=""
ENCOUNTER_PID=""
ENCOUNTER_DATE=""
ENCOUNTER_REASON=""
ENCOUNTER_NUM=""
ENCOUNTER_CATID=""
ENCOUNTER_FACILITY=""
ENCOUNTER_PROVIDER=""
IS_NEW_ENCOUNTER="false"

if [ -n "$NEWEST_ENCOUNTER" ]; then
    ENCOUNTER_FOUND="true"
    # Parse tab-separated values
    ENCOUNTER_ID=$(echo "$NEWEST_ENCOUNTER" | cut -f1)
    ENCOUNTER_PID=$(echo "$NEWEST_ENCOUNTER" | cut -f2)
    ENCOUNTER_DATE=$(echo "$NEWEST_ENCOUNTER" | cut -f3)
    ENCOUNTER_REASON=$(echo "$NEWEST_ENCOUNTER" | cut -f4)
    ENCOUNTER_NUM=$(echo "$NEWEST_ENCOUNTER" | cut -f5)
    ENCOUNTER_CATID=$(echo "$NEWEST_ENCOUNTER" | cut -f6)
    ENCOUNTER_FACILITY=$(echo "$NEWEST_ENCOUNTER" | cut -f7)
    ENCOUNTER_PROVIDER=$(echo "$NEWEST_ENCOUNTER" | cut -f8)
    
    echo ""
    echo "Most recent encounter for patient:"
    echo "  ID: $ENCOUNTER_ID"
    echo "  PID: $ENCOUNTER_PID"
    echo "  Date: $ENCOUNTER_DATE"
    echo "  Reason: $ENCOUNTER_REASON"
    echo "  Encounter#: $ENCOUNTER_NUM"
    echo "  Category: $ENCOUNTER_CATID"
    
    # Check if this is a NEW encounter (created during task)
    if [ -n "$ENCOUNTER_ID" ] && [ "$ENCOUNTER_ID" -gt "$HIGHEST_INITIAL_ID" ]; then
        IS_NEW_ENCOUNTER="true"
        echo "  Status: NEW (id $ENCOUNTER_ID > initial max $HIGHEST_INITIAL_ID)"
    else
        echo "  Status: PRE-EXISTING (not created during task)"
    fi
else
    echo "No encounters found for patient PID=$PATIENT_PID"
fi

# Check if encounter count increased
ENCOUNTER_COUNT_INCREASED="false"
if [ "$CURRENT_ENCOUNTER_COUNT" -gt "$INITIAL_ENCOUNTER_COUNT" ]; then
    ENCOUNTER_COUNT_INCREASED="true"
    NEW_COUNT=$((CURRENT_ENCOUNTER_COUNT - INITIAL_ENCOUNTER_COUNT))
    echo "Encounter count increased by $NEW_COUNT"
fi

# Validate encounter date is today or recent
TODAY=$(date +%Y-%m-%d)
DATE_VALID="false"
if [ -n "$ENCOUNTER_DATE" ]; then
    # Check if date matches today
    if [ "$ENCOUNTER_DATE" = "$TODAY" ]; then
        DATE_VALID="true"
        echo "Date is valid (today: $TODAY)"
    elif [ "$ENCOUNTER_DATE" \> "$(date -d '-1 day' +%Y-%m-%d)" ]; then
        DATE_VALID="true"
        echo "Date is valid (recent: $ENCOUNTER_DATE)"
    else
        echo "Date may not be valid: $ENCOUNTER_DATE (expected around $TODAY)"
    fi
fi

# Check if reason contains expected keywords (back, pain, lower)
REASON_VALID="false"
if [ -n "$ENCOUNTER_REASON" ]; then
    REASON_LOWER=$(echo "$ENCOUNTER_REASON" | tr '[:upper:]' '[:lower:]')
    if echo "$REASON_LOWER" | grep -qE "(back|pain|lower)"; then
        REASON_VALID="true"
        echo "Reason contains expected keywords"
    else
        echo "Reason does not contain expected keywords: $ENCOUNTER_REASON"
    fi
fi

# Check if Firefox/OpenEMR was running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null 2>&1; then
    FIREFOX_RUNNING="true"
fi

# Escape special characters for JSON
ENCOUNTER_REASON_ESCAPED=$(echo "$ENCOUNTER_REASON" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/encounter_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "patient_pid": $PATIENT_PID,
    "initial_encounter_count": ${INITIAL_ENCOUNTER_COUNT:-0},
    "current_encounter_count": ${CURRENT_ENCOUNTER_COUNT:-0},
    "highest_initial_encounter_id": ${HIGHEST_INITIAL_ID:-0},
    "encounter_count_increased": $ENCOUNTER_COUNT_INCREASED,
    "encounter_found": $ENCOUNTER_FOUND,
    "is_new_encounter": $IS_NEW_ENCOUNTER,
    "encounter": {
        "id": "$ENCOUNTER_ID",
        "pid": "$ENCOUNTER_PID",
        "date": "$ENCOUNTER_DATE",
        "reason": "$ENCOUNTER_REASON_ESCAPED",
        "encounter_number": "$ENCOUNTER_NUM",
        "category_id": "$ENCOUNTER_CATID",
        "facility_id": "$ENCOUNTER_FACILITY",
        "provider_id": "$ENCOUNTER_PROVIDER"
    },
    "validation": {
        "date_valid": $DATE_VALID,
        "reason_valid": $REASON_VALID,
        "correct_patient": $([ "$ENCOUNTER_PID" = "$PATIENT_PID" ] && echo "true" || echo "false")
    },
    "environment": {
        "firefox_running": $FIREFOX_RUNNING,
        "today_date": "$TODAY",
        "final_screenshot": "/tmp/task_final_state.png"
    }
}
EOF

# Move to final location with permission handling
rm -f /tmp/create_encounter_result.json 2>/dev/null || sudo rm -f /tmp/create_encounter_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_encounter_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_encounter_result.json
chmod 666 /tmp/create_encounter_result.json 2>/dev/null || sudo chmod 666 /tmp/create_encounter_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_encounter_result.json"
cat /tmp/create_encounter_result.json
echo ""
echo "=== Export Complete ==="