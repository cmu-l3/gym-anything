#!/bin/bash
# Export script for Record Pain Assessment Task

echo "=== Exporting Pain Assessment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved"

# Get task timing info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get target patient info
if [ -f /tmp/target_patient.json ]; then
    PATIENT_PID=$(grep -o '"pid": "[^"]*"' /tmp/target_patient.json | cut -d'"' -f4)
    PATIENT_FNAME=$(grep -o '"fname": "[^"]*"' /tmp/target_patient.json | cut -d'"' -f4)
    PATIENT_LNAME=$(grep -o '"lname": "[^"]*"' /tmp/target_patient.json | cut -d'"' -f4)
else
    PATIENT_PID="1"
    PATIENT_FNAME="Unknown"
    PATIENT_LNAME="Unknown"
fi

echo "Target patient: PID=$PATIENT_PID, Name='$PATIENT_FNAME $PATIENT_LNAME'"

# Get initial counts
INITIAL_VITALS_COUNT=$(cat /tmp/initial_vitals_count 2>/dev/null || echo "0")
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Vitals count: initial=$INITIAL_VITALS_COUNT, current=$CURRENT_VITALS_COUNT"
echo "Encounter count: initial=$INITIAL_ENCOUNTER_COUNT, current=$CURRENT_ENCOUNTER_COUNT"

# Query for vitals with pain scores for this patient
echo ""
echo "=== Querying pain records for patient PID=$PATIENT_PID ==="

# Get all vitals entries with pain data, ordered by most recent
ALL_VITALS=$(openemr_query "SELECT id, pid, encounter, date, pain, note, user FROM form_vitals WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "All vitals for patient:"
echo "$ALL_VITALS"

# Find the most recent vitals entry (highest ID = newest)
NEWEST_VITALS=$(openemr_query "SELECT id, pid, encounter, date, pain, note, user FROM form_vitals WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse vitals data
VITALS_FOUND="false"
VITALS_ID=""
VITALS_ENCOUNTER=""
VITALS_DATE=""
PAIN_SCORE=""
VITALS_NOTE=""
VITALS_USER=""

if [ -n "$NEWEST_VITALS" ] && [ "$CURRENT_VITALS_COUNT" -gt "$INITIAL_VITALS_COUNT" ]; then
    VITALS_FOUND="true"
    VITALS_ID=$(echo "$NEWEST_VITALS" | cut -f1)
    VITALS_PID=$(echo "$NEWEST_VITALS" | cut -f2)
    VITALS_ENCOUNTER=$(echo "$NEWEST_VITALS" | cut -f3)
    VITALS_DATE=$(echo "$NEWEST_VITALS" | cut -f4)
    PAIN_SCORE=$(echo "$NEWEST_VITALS" | cut -f5)
    VITALS_NOTE=$(echo "$NEWEST_VITALS" | cut -f6)
    VITALS_USER=$(echo "$NEWEST_VITALS" | cut -f7)
    
    echo ""
    echo "New vitals record found:"
    echo "  ID: $VITALS_ID"
    echo "  Patient PID: $VITALS_PID"
    echo "  Encounter: $VITALS_ENCOUNTER"
    echo "  Date: $VITALS_DATE"
    echo "  Pain Score: '$PAIN_SCORE'"
    echo "  Note: '$VITALS_NOTE'"
    echo "  User: $VITALS_USER"
else
    echo "No new vitals record found for patient"
    
    # Check if pain was recorded in the most recent vitals even if count didn't change
    LATEST_PAIN=$(openemr_query "SELECT id, pain, note, date FROM form_vitals WHERE pid=$PATIENT_PID AND pain IS NOT NULL AND pain != '' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$LATEST_PAIN" ]; then
        echo "Found existing vitals with pain data:"
        echo "$LATEST_PAIN"
        
        # Check if this entry was modified recently (within task time)
        VITALS_ID=$(echo "$LATEST_PAIN" | cut -f1)
        PAIN_SCORE=$(echo "$LATEST_PAIN" | cut -f2)
        VITALS_NOTE=$(echo "$LATEST_PAIN" | cut -f3)
        VITALS_DATE=$(echo "$LATEST_PAIN" | cut -f4)
        
        # Convert date to epoch for comparison
        if [ -n "$VITALS_DATE" ]; then
            VITALS_EPOCH=$(date -d "$VITALS_DATE" +%s 2>/dev/null || echo "0")
            if [ "$VITALS_EPOCH" -ge "$TASK_START" ]; then
                VITALS_FOUND="true"
                echo "Vitals entry was created/modified during task"
            fi
        fi
    fi
fi

# Check for new encounters
NEW_ENCOUNTER_FOUND="false"
ENCOUNTER_ID=""
if [ "$CURRENT_ENCOUNTER_COUNT" -gt "$INITIAL_ENCOUNTER_COUNT" ]; then
    NEW_ENCOUNTER_FOUND="true"
    ENCOUNTER_ID=$(openemr_query "SELECT id FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "New encounter created: ID=$ENCOUNTER_ID"
fi

# Check if pain score is correct (7)
PAIN_SCORE_CORRECT="false"
if [ "$PAIN_SCORE" = "7" ]; then
    PAIN_SCORE_CORRECT="true"
fi

# Check if location is documented in notes
LOCATION_DOCUMENTED="false"
NOTE_LOWER=$(echo "$VITALS_NOTE" | tr '[:upper:]' '[:lower:]')
if echo "$NOTE_LOWER" | grep -qE "(lower back|lumbar|back|spine|l[0-9])"; then
    LOCATION_DOCUMENTED="true"
fi

# Escape special characters for JSON
VITALS_NOTE_ESCAPED=$(echo "$VITALS_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/pain_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient": {
        "pid": "$PATIENT_PID",
        "fname": "$PATIENT_FNAME",
        "lname": "$PATIENT_LNAME"
    },
    "initial_vitals_count": ${INITIAL_VITALS_COUNT:-0},
    "current_vitals_count": ${CURRENT_VITALS_COUNT:-0},
    "initial_encounter_count": ${INITIAL_ENCOUNTER_COUNT:-0},
    "current_encounter_count": ${CURRENT_ENCOUNTER_COUNT:-0},
    "new_vitals_found": $VITALS_FOUND,
    "new_encounter_found": $NEW_ENCOUNTER_FOUND,
    "vitals": {
        "id": "$VITALS_ID",
        "encounter_id": "$VITALS_ENCOUNTER",
        "date": "$VITALS_DATE",
        "pain_score": "$PAIN_SCORE",
        "note": "$VITALS_NOTE_ESCAPED",
        "user": "$VITALS_USER"
    },
    "validation": {
        "pain_score_correct": $PAIN_SCORE_CORRECT,
        "location_documented": $LOCATION_DOCUMENTED
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Save result
rm -f /tmp/pain_assessment_result.json 2>/dev/null || sudo rm -f /tmp/pain_assessment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pain_assessment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pain_assessment_result.json
chmod 666 /tmp/pain_assessment_result.json 2>/dev/null || sudo chmod 666 /tmp/pain_assessment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/pain_assessment_result.json"
cat /tmp/pain_assessment_result.json
echo ""
echo "=== Export Complete ==="