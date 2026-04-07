#!/bin/bash
# Export script for Discontinue Medication task

echo "=== Exporting Discontinue Medication Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved to /tmp/task_final_state.png"

# Target patient and medication
PATIENT_PID=3
MEDICATION_PATTERN="amLODIPine"

# Load baseline state
BASELINE_FILE="/tmp/baseline_medication_state.json"
if [ -f "$BASELINE_FILE" ]; then
    BASELINE_MED_ID=$(python3 -c "import json; print(json.load(open('$BASELINE_FILE')).get('medication_id', '0'))" 2>/dev/null || echo "0")
    BASELINE_ACTIVE=$(python3 -c "import json; print(json.load(open('$BASELINE_FILE')).get('initial_active_status', 'unknown'))" 2>/dev/null || echo "unknown")
else
    BASELINE_MED_ID="0"
    BASELINE_ACTIVE="unknown"
fi

echo "Baseline state: med_id=$BASELINE_MED_ID, active=$BASELINE_ACTIVE"

# Query current medication state
echo ""
echo "=== Querying current medication state ==="

# Get the full medication record
CURRENT_MED=$(openemr_query "SELECT id, drug, active, date_modified, rxnorm_drugcode FROM prescriptions WHERE patient_id=$PATIENT_PID AND drug LIKE '%$MEDICATION_PATTERN%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

echo "Current medication record: $CURRENT_MED"

# Parse current medication data
MED_FOUND="false"
MED_ID=""
MED_DRUG=""
MED_ACTIVE=""
MED_MODIFIED=""
MED_RXNORM=""

if [ -n "$CURRENT_MED" ]; then
    MED_FOUND="true"
    MED_ID=$(echo "$CURRENT_MED" | cut -f1)
    MED_DRUG=$(echo "$CURRENT_MED" | cut -f2)
    MED_ACTIVE=$(echo "$CURRENT_MED" | cut -f3)
    MED_MODIFIED=$(echo "$CURRENT_MED" | cut -f4)
    MED_RXNORM=$(echo "$CURRENT_MED" | cut -f5)
    
    echo "  ID: $MED_ID"
    echo "  Drug: $MED_DRUG"
    echo "  Active: $MED_ACTIVE"
    echo "  Modified: $MED_MODIFIED"
fi

# Check if medication was modified during the task
MED_MODIFIED_DURING_TASK="false"
if [ -n "$MED_MODIFIED" ] && [ "$MED_MODIFIED" != "NULL" ]; then
    # Convert datetime to epoch for comparison
    MED_MODIFIED_EPOCH=$(date -d "$MED_MODIFIED" +%s 2>/dev/null || echo "0")
    if [ "$MED_MODIFIED_EPOCH" -gt "$TASK_START" ]; then
        MED_MODIFIED_DURING_TASK="true"
        echo "Medication was modified during task (modified=$MED_MODIFIED_EPOCH, start=$TASK_START)"
    else
        echo "Medication NOT modified during task (modified=$MED_MODIFIED_EPOCH, start=$TASK_START)"
    fi
fi

# Check for discontinue-specific fields (OpenEMR might use different field names)
# Try to get end_date, discontinue_date, or similar
echo ""
echo "=== Checking for discontinuation details ==="

DISCONTINUE_DETAILS=$(openemr_query "SELECT end_date, note, erx_source FROM prescriptions WHERE id='$MED_ID'" 2>/dev/null || echo "")
echo "Discontinue details: $DISCONTINUE_DETAILS"

# Try additional fields that might exist
# Note: OpenEMR schema varies by version, so we check multiple possibilities
END_DATE=$(echo "$DISCONTINUE_DETAILS" | cut -f1)
MED_NOTE=$(echo "$DISCONTINUE_DETAILS" | cut -f2)

# Also check the lists table for medication_stoplist or similar
STOPLIST_CHECK=$(openemr_query "SELECT id, title, comments FROM lists WHERE pid=$PATIENT_PID AND type='medication' AND (title LIKE '%$MEDICATION_PATTERN%' OR title LIKE '%stop%') ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
echo "Stoplist check: $STOPLIST_CHECK"

# Check if the medication is now marked inactive
MEDICATION_DISCONTINUED="false"
if [ "$MED_ACTIVE" = "0" ]; then
    MEDICATION_DISCONTINUED="true"
    echo "Medication is marked INACTIVE (discontinued)"
elif [ -n "$END_DATE" ] && [ "$END_DATE" != "NULL" ] && [ "$END_DATE" != "0000-00-00" ]; then
    MEDICATION_DISCONTINUED="true"
    echo "Medication has end_date set: $END_DATE"
else
    echo "Medication appears to still be active"
fi

# Check if there's any reason/note related to edema or side effect
REASON_FOUND="false"
REASON_TEXT=""
MED_NOTE_LOWER=$(echo "$MED_NOTE" | tr '[:upper:]' '[:lower:]')
if echo "$MED_NOTE_LOWER" | grep -qE "(edema|swelling|side.?effect|adverse|ankle)"; then
    REASON_FOUND="true"
    REASON_TEXT="$MED_NOTE"
    echo "Discontinue reason found in note: $REASON_TEXT"
fi

# Also check for any recent amendments or clinical notes
echo ""
echo "=== Checking recent notes ==="
RECENT_NOTES=$(openemr_query "SELECT id, body FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 3" 2>/dev/null || echo "")
echo "Recent notes: $RECENT_NOTES"

# Escape special characters for JSON
MED_DRUG_ESCAPED=$(echo "$MED_DRUG" | sed 's/"/\\"/g' | tr '\n' ' ')
MED_NOTE_ESCAPED=$(echo "$MED_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ')
REASON_TEXT_ESCAPED=$(echo "$REASON_TEXT" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/discontinue_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_timing": {
        "start": $TASK_START,
        "end": $TASK_END,
        "duration_seconds": $((TASK_END - TASK_START))
    },
    "baseline": {
        "medication_id": "$BASELINE_MED_ID",
        "initial_active_status": "$BASELINE_ACTIVE"
    },
    "current_state": {
        "medication_found": $MED_FOUND,
        "medication_id": "$MED_ID",
        "drug_name": "$MED_DRUG_ESCAPED",
        "active_status": "$MED_ACTIVE",
        "date_modified": "$MED_MODIFIED",
        "end_date": "$END_DATE",
        "note": "$MED_NOTE_ESCAPED",
        "rxnorm_code": "$MED_RXNORM"
    },
    "verification": {
        "medication_discontinued": $MEDICATION_DISCONTINUED,
        "modified_during_task": $MED_MODIFIED_DURING_TASK,
        "reason_documented": $REASON_FOUND,
        "reason_text": "$REASON_TEXT_ESCAPED"
    },
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final_state.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/discontinue_medication_result.json 2>/dev/null || sudo rm -f /tmp/discontinue_medication_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/discontinue_medication_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/discontinue_medication_result.json
chmod 666 /tmp/discontinue_medication_result.json 2>/dev/null || sudo chmod 666 /tmp/discontinue_medication_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/discontinue_medication_result.json:"
cat /tmp/discontinue_medication_result.json

echo ""
echo "=== Export Complete ==="