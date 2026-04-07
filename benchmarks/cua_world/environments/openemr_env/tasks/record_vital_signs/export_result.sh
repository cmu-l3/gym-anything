#!/bin/bash
# Export script for Record Vital Signs task

echo "=== Exporting Record Vital Signs Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
if [ -f /tmp/task_final.png ]; then
    echo "Final screenshot captured"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Target patient
PATIENT_PID=3

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_VITALS_COUNT=$(cat /tmp/initial_vitals_count.txt 2>/dev/null || echo "0")
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals fv JOIN forms f ON f.form_id = fv.id AND f.formdir = 'vitals' WHERE fv.pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Vitals count: initial=$INITIAL_VITALS_COUNT, current=$CURRENT_VITALS_COUNT"
echo "Encounter count: initial=$INITIAL_ENCOUNTER_COUNT, current=$CURRENT_ENCOUNTER_COUNT"

# Query for the most recent vital signs for this patient
echo ""
echo "=== Querying vital signs for patient PID=$PATIENT_PID ==="

# Get the most recent vitals record with form linkage
VITALS_QUERY="SELECT fv.id, fv.pid, fv.bps, fv.bpd, fv.pulse, fv.temperature, fv.respiration, fv.oxygen_saturation, fv.weight, fv.height, fv.BMI, f.date, f.encounter FROM form_vitals fv JOIN forms f ON f.form_id = fv.id AND f.formdir = 'vitals' WHERE fv.pid=$PATIENT_PID ORDER BY f.date DESC, fv.id DESC LIMIT 1"

VITALS_DATA=$(openemr_query "$VITALS_QUERY" 2>/dev/null)
echo "Vitals query result: $VITALS_DATA"

# Debug: Show all recent vitals
echo ""
echo "=== DEBUG: All vitals for patient ==="
openemr_query "SELECT fv.id, fv.bps, fv.bpd, fv.pulse, fv.temperature, fv.respiration, fv.oxygen_saturation, fv.weight, fv.height, f.date FROM form_vitals fv JOIN forms f ON f.form_id = fv.id AND f.formdir = 'vitals' WHERE fv.pid=$PATIENT_PID ORDER BY fv.id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="

# Parse vitals data
VITALS_FOUND="false"
VITALS_ID=""
VITALS_BPS=""
VITALS_BPD=""
VITALS_PULSE=""
VITALS_TEMP=""
VITALS_RESP=""
VITALS_O2=""
VITALS_WEIGHT=""
VITALS_HEIGHT=""
VITALS_BMI=""
VITALS_DATE=""
VITALS_ENCOUNTER=""

if [ -n "$VITALS_DATA" ] && [ "$CURRENT_VITALS_COUNT" -gt "$INITIAL_VITALS_COUNT" ]; then
    VITALS_FOUND="true"
    VITALS_ID=$(echo "$VITALS_DATA" | cut -f1)
    VITALS_PID=$(echo "$VITALS_DATA" | cut -f2)
    VITALS_BPS=$(echo "$VITALS_DATA" | cut -f3)
    VITALS_BPD=$(echo "$VITALS_DATA" | cut -f4)
    VITALS_PULSE=$(echo "$VITALS_DATA" | cut -f5)
    VITALS_TEMP=$(echo "$VITALS_DATA" | cut -f6)
    VITALS_RESP=$(echo "$VITALS_DATA" | cut -f7)
    VITALS_O2=$(echo "$VITALS_DATA" | cut -f8)
    VITALS_WEIGHT=$(echo "$VITALS_DATA" | cut -f9)
    VITALS_HEIGHT=$(echo "$VITALS_DATA" | cut -f10)
    VITALS_BMI=$(echo "$VITALS_DATA" | cut -f11)
    VITALS_DATE=$(echo "$VITALS_DATA" | cut -f12)
    VITALS_ENCOUNTER=$(echo "$VITALS_DATA" | cut -f13)
    
    echo ""
    echo "New vitals found:"
    echo "  ID: $VITALS_ID"
    echo "  BP: $VITALS_BPS/$VITALS_BPD mmHg"
    echo "  Pulse: $VITALS_PULSE bpm"
    echo "  Temperature: $VITALS_TEMP °F"
    echo "  Respiration: $VITALS_RESP breaths/min"
    echo "  O2 Sat: $VITALS_O2%"
    echo "  Weight: $VITALS_WEIGHT lbs"
    echo "  Height: $VITALS_HEIGHT inches"
    echo "  BMI: $VITALS_BMI"
    echo "  Date: $VITALS_DATE"
    echo "  Encounter: $VITALS_ENCOUNTER"
else
    echo "No new vital signs found for patient"
fi

# Check for new encounter
ENCOUNTER_FOUND="false"
ENCOUNTER_ID=""
ENCOUNTER_DATE=""
ENCOUNTER_REASON=""

if [ "$CURRENT_ENCOUNTER_COUNT" -gt "$INITIAL_ENCOUNTER_COUNT" ]; then
    ENCOUNTER_FOUND="true"
    ENCOUNTER_DATA=$(openemr_query "SELECT id, date, reason FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    ENCOUNTER_ID=$(echo "$ENCOUNTER_DATA" | cut -f1)
    ENCOUNTER_DATE=$(echo "$ENCOUNTER_DATA" | cut -f2)
    ENCOUNTER_REASON=$(echo "$ENCOUNTER_DATA" | cut -f3)
    echo ""
    echo "New encounter found:"
    echo "  ID: $ENCOUNTER_ID"
    echo "  Date: $ENCOUNTER_DATE"
    echo "  Reason: $ENCOUNTER_REASON"
fi

# Escape special characters for JSON
ENCOUNTER_REASON_ESCAPED=$(echo "$ENCOUNTER_REASON" | sed 's/"/\\"/g' | tr '\n' ' ')

# Handle NULL/empty values for JSON
[ -z "$VITALS_BPS" ] && VITALS_BPS="null"
[ -z "$VITALS_BPD" ] && VITALS_BPD="null"
[ -z "$VITALS_PULSE" ] && VITALS_PULSE="null"
[ -z "$VITALS_TEMP" ] && VITALS_TEMP="null"
[ -z "$VITALS_RESP" ] && VITALS_RESP="null"
[ -z "$VITALS_O2" ] && VITALS_O2="null"
[ -z "$VITALS_WEIGHT" ] && VITALS_WEIGHT="null"
[ -z "$VITALS_HEIGHT" ] && VITALS_HEIGHT="null"
[ -z "$VITALS_BMI" ] && VITALS_BMI="null"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/vitals_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_vitals_count": ${INITIAL_VITALS_COUNT:-0},
    "current_vitals_count": ${CURRENT_VITALS_COUNT:-0},
    "initial_encounter_count": ${INITIAL_ENCOUNTER_COUNT:-0},
    "current_encounter_count": ${CURRENT_ENCOUNTER_COUNT:-0},
    "new_vitals_found": $VITALS_FOUND,
    "new_encounter_found": $ENCOUNTER_FOUND,
    "vitals": {
        "id": "$VITALS_ID",
        "bps": $VITALS_BPS,
        "bpd": $VITALS_BPD,
        "pulse": $VITALS_PULSE,
        "temperature": $VITALS_TEMP,
        "respiration": $VITALS_RESP,
        "oxygen_saturation": $VITALS_O2,
        "weight": $VITALS_WEIGHT,
        "height": $VITALS_HEIGHT,
        "bmi": $VITALS_BMI,
        "date": "$VITALS_DATE",
        "encounter_id": "$VITALS_ENCOUNTER"
    },
    "encounter": {
        "id": "$ENCOUNTER_ID",
        "date": "$ENCOUNTER_DATE",
        "reason": "$ENCOUNTER_REASON_ESCAPED"
    },
    "screenshot_final": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="