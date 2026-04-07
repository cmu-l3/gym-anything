#!/bin/bash
# Export script for Record Current Medication task

echo "=== Exporting Record Current Medication Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved"

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count.txt 2>/dev/null || echo "0")
INITIAL_MEDLIST_COUNT=$(cat /tmp/initial_medlist_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_MEDLIST_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medication'" 2>/dev/null || echo "0")

echo "Medication counts:"
echo "  Prescriptions: initial=$INITIAL_RX_COUNT, current=$CURRENT_RX_COUNT"
echo "  Medication list: initial=$INITIAL_MEDLIST_COUNT, current=$CURRENT_MEDLIST_COUNT"

# Search for Metformin in prescriptions table
echo ""
echo "=== Searching for Metformin in prescriptions table ==="
METFORMIN_RX=$(openemr_query "SELECT id, patient_id, drug, dosage, form, route, unit, size, date_added, active FROM prescriptions WHERE patient_id=$PATIENT_PID AND LOWER(drug) LIKE '%metformin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "Metformin in prescriptions: $METFORMIN_RX"

# Search for Metformin in lists table (medication type)
echo ""
echo "=== Searching for Metformin in lists table ==="
METFORMIN_LIST=$(openemr_query "SELECT id, pid, type, title, begdate, activity, comments FROM lists WHERE pid=$PATIENT_PID AND type='medication' AND LOWER(title) LIKE '%metformin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "Metformin in lists: $METFORMIN_LIST"

# Debug: Show all recent prescriptions for this patient
echo ""
echo "=== DEBUG: Recent prescriptions for patient ==="
openemr_query "SELECT id, drug, dosage, date_added, active FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null

# Debug: Show all medications in lists for this patient
echo ""
echo "=== DEBUG: Medications in lists table for patient ==="
openemr_query "SELECT id, title, begdate, activity FROM lists WHERE pid=$PATIENT_PID AND type='medication' ORDER BY id DESC LIMIT 5" 2>/dev/null

# Parse Metformin data from prescriptions
RX_FOUND="false"
RX_ID=""
RX_DRUG=""
RX_DOSAGE=""
RX_FORM=""
RX_DATE_ADDED=""
RX_ACTIVE="0"

if [ -n "$METFORMIN_RX" ]; then
    RX_FOUND="true"
    RX_ID=$(echo "$METFORMIN_RX" | cut -f1)
    RX_PATIENT_ID=$(echo "$METFORMIN_RX" | cut -f2)
    RX_DRUG=$(echo "$METFORMIN_RX" | cut -f3)
    RX_DOSAGE=$(echo "$METFORMIN_RX" | cut -f4)
    RX_FORM=$(echo "$METFORMIN_RX" | cut -f5)
    RX_ROUTE=$(echo "$METFORMIN_RX" | cut -f6)
    RX_UNIT=$(echo "$METFORMIN_RX" | cut -f7)
    RX_SIZE=$(echo "$METFORMIN_RX" | cut -f8)
    RX_DATE_ADDED=$(echo "$METFORMIN_RX" | cut -f9)
    RX_ACTIVE=$(echo "$METFORMIN_RX" | cut -f10)
    echo ""
    echo "Metformin found in prescriptions:"
    echo "  ID: $RX_ID"
    echo "  Drug: $RX_DRUG"
    echo "  Dosage: $RX_DOSAGE"
    echo "  Form: $RX_FORM"
    echo "  Date Added: $RX_DATE_ADDED"
    echo "  Active: $RX_ACTIVE"
fi

# Parse Metformin data from lists
LIST_FOUND="false"
LIST_ID=""
LIST_TITLE=""
LIST_BEGDATE=""
LIST_ACTIVITY="0"
LIST_COMMENTS=""

if [ -n "$METFORMIN_LIST" ]; then
    LIST_FOUND="true"
    LIST_ID=$(echo "$METFORMIN_LIST" | cut -f1)
    LIST_PID=$(echo "$METFORMIN_LIST" | cut -f2)
    LIST_TYPE=$(echo "$METFORMIN_LIST" | cut -f3)
    LIST_TITLE=$(echo "$METFORMIN_LIST" | cut -f4)
    LIST_BEGDATE=$(echo "$METFORMIN_LIST" | cut -f5)
    LIST_ACTIVITY=$(echo "$METFORMIN_LIST" | cut -f6)
    LIST_COMMENTS=$(echo "$METFORMIN_LIST" | cut -f7)
    echo ""
    echo "Metformin found in lists:"
    echo "  ID: $LIST_ID"
    echo "  Title: $LIST_TITLE"
    echo "  Begin Date: $LIST_BEGDATE"
    echo "  Activity: $LIST_ACTIVITY"
fi

# Determine if any new medication entry was created
NEW_ENTRY_CREATED="false"
if [ "$CURRENT_RX_COUNT" -gt "$INITIAL_RX_COUNT" ] || [ "$CURRENT_MEDLIST_COUNT" -gt "$INITIAL_MEDLIST_COUNT" ]; then
    NEW_ENTRY_CREATED="true"
fi

# Escape special characters for JSON
RX_DRUG_ESCAPED=$(echo "$RX_DRUG" | sed 's/"/\\"/g' | tr '\n' ' ')
RX_DOSAGE_ESCAPED=$(echo "$RX_DOSAGE" | sed 's/"/\\"/g' | tr '\n' ' ')
LIST_TITLE_ESCAPED=$(echo "$LIST_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')
LIST_COMMENTS_ESCAPED=$(echo "$LIST_COMMENTS" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/med_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_rx_count": ${INITIAL_RX_COUNT:-0},
    "current_rx_count": ${CURRENT_RX_COUNT:-0},
    "initial_medlist_count": ${INITIAL_MEDLIST_COUNT:-0},
    "current_medlist_count": ${CURRENT_MEDLIST_COUNT:-0},
    "new_entry_created": $NEW_ENTRY_CREATED,
    "prescriptions_entry": {
        "found": $RX_FOUND,
        "id": "$RX_ID",
        "drug": "$RX_DRUG_ESCAPED",
        "dosage": "$RX_DOSAGE_ESCAPED",
        "form": "$RX_FORM",
        "date_added": "$RX_DATE_ADDED",
        "active": "$RX_ACTIVE"
    },
    "lists_entry": {
        "found": $LIST_FOUND,
        "id": "$LIST_ID",
        "title": "$LIST_TITLE_ESCAPED",
        "begdate": "$LIST_BEGDATE",
        "activity": "$LIST_ACTIVITY",
        "comments": "$LIST_COMMENTS_ESCAPED"
    },
    "screenshot_final": "/tmp/task_final_state.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result to known location
rm -f /tmp/record_medication_result.json 2>/dev/null || sudo rm -f /tmp/record_medication_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_medication_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_medication_result.json
chmod 666 /tmp/record_medication_result.json 2>/dev/null || sudo chmod 666 /tmp/record_medication_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/record_medication_result.json
echo ""
echo "=== Export Complete ==="