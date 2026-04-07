#!/bin/bash
# Export script for Renew Prescription task

echo "=== Exporting Renew Prescription Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=3

# Get timestamps and initial counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_RX=$(cat /tmp/initial_total_rx_count.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_rx_id.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Initial counts: patient_rx=$INITIAL_RX_COUNT, total_rx=$INITIAL_TOTAL_RX, max_id=$INITIAL_MAX_ID"

# Get current prescription count for patient
CURRENT_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL_RX=$(openemr_query "SELECT COUNT(*) FROM prescriptions" 2>/dev/null || echo "0")

echo "Current counts: patient_rx=$CURRENT_RX_COUNT, total_rx=$CURRENT_TOTAL_RX"

# Query for new prescriptions created after task start
# Look for prescriptions with ID > initial max ID for this patient
echo ""
echo "=== Querying for new prescriptions for patient PID=$PATIENT_PID ==="

# Get all recent prescriptions for this patient (ordered by id desc)
ALL_PATIENT_RX=$(openemr_query "SELECT id, drug, dosage, quantity, refills, date_added, UNIX_TIMESTAMP(date_modified) as modified_ts FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "Recent prescriptions for patient:"
echo "$ALL_PATIENT_RX"

# Find NEW prescriptions (id > initial max id) for this patient
NEW_RX=$(openemr_query "SELECT id, drug, dosage, quantity, refills, date_added, UNIX_TIMESTAMP(date_modified) as modified_ts FROM prescriptions WHERE patient_id=$PATIENT_PID AND id > $INITIAL_MAX_ID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse new prescription data
NEW_RX_FOUND="false"
RX_ID=""
RX_DRUG=""
RX_DOSAGE=""
RX_QUANTITY=""
RX_REFILLS=""
RX_DATE_ADDED=""
RX_MODIFIED_TS=""

if [ -n "$NEW_RX" ]; then
    NEW_RX_FOUND="true"
    RX_ID=$(echo "$NEW_RX" | cut -f1)
    RX_DRUG=$(echo "$NEW_RX" | cut -f2)
    RX_DOSAGE=$(echo "$NEW_RX" | cut -f3)
    RX_QUANTITY=$(echo "$NEW_RX" | cut -f4)
    RX_REFILLS=$(echo "$NEW_RX" | cut -f5)
    RX_DATE_ADDED=$(echo "$NEW_RX" | cut -f6)
    RX_MODIFIED_TS=$(echo "$NEW_RX" | cut -f7)
    
    echo ""
    echo "New prescription found:"
    echo "  ID: $RX_ID"
    echo "  Drug: $RX_DRUG"
    echo "  Dosage: $RX_DOSAGE"
    echo "  Quantity: $RX_QUANTITY"
    echo "  Refills: $RX_REFILLS"
    echo "  Date Added: $RX_DATE_ADDED"
    echo "  Modified TS: $RX_MODIFIED_TS"
else
    echo "No new prescription found for patient (id > $INITIAL_MAX_ID)"
fi

# Check if drug contains amLODIPine (case-insensitive)
DRUG_VALID="false"
RX_DRUG_LOWER=$(echo "$RX_DRUG" | tr '[:upper:]' '[:lower:]')
if echo "$RX_DRUG_LOWER" | grep -q "amlodipine"; then
    DRUG_VALID="true"
    echo "Drug contains amLODIPine: YES"
else
    echo "Drug contains amLODIPine: NO (drug='$RX_DRUG')"
fi

# Check quantity (expected 90, tolerance ±10)
QUANTITY_VALID="false"
if [ -n "$RX_QUANTITY" ]; then
    # Handle potential non-numeric values
    QTY_NUM=$(echo "$RX_QUANTITY" | grep -oE '^[0-9]+' || echo "0")
    if [ "$QTY_NUM" -ge 80 ] && [ "$QTY_NUM" -le 100 ]; then
        QUANTITY_VALID="true"
        echo "Quantity valid: YES ($QTY_NUM is within 80-100)"
    else
        echo "Quantity valid: NO ($QTY_NUM not within 80-100)"
    fi
fi

# Check refills (expected 3, tolerance ±1)
REFILLS_VALID="false"
if [ -n "$RX_REFILLS" ]; then
    REF_NUM=$(echo "$RX_REFILLS" | grep -oE '^[0-9]+' || echo "0")
    if [ "$REF_NUM" -ge 2 ] && [ "$REF_NUM" -le 4 ]; then
        REFILLS_VALID="true"
        echo "Refills valid: YES ($REF_NUM is within 2-4)"
    else
        echo "Refills valid: NO ($REF_NUM not within 2-4)"
    fi
fi

# Check if prescription was created today
TODAY=$(date +%Y-%m-%d)
DATE_VALID="false"
if [ "$RX_DATE_ADDED" = "$TODAY" ]; then
    DATE_VALID="true"
    echo "Date valid: YES (created today: $TODAY)"
else
    # Also check modified timestamp against task start
    if [ -n "$RX_MODIFIED_TS" ] && [ "$RX_MODIFIED_TS" -gt "$TASK_START" ]; then
        DATE_VALID="true"
        echo "Date valid: YES (modified during task)"
    else
        echo "Date valid: NO (date_added=$RX_DATE_ADDED, today=$TODAY)"
    fi
fi

# Escape special characters for JSON
RX_DRUG_ESCAPED=$(echo "$RX_DRUG" | sed 's/"/\\"/g' | tr '\n' ' ')
RX_DOSAGE_ESCAPED=$(echo "$RX_DOSAGE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/rx_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_rx_count": ${INITIAL_RX_COUNT:-0},
    "current_rx_count": ${CURRENT_RX_COUNT:-0},
    "initial_max_rx_id": ${INITIAL_MAX_ID:-0},
    "new_prescription_found": $NEW_RX_FOUND,
    "prescription": {
        "id": "$RX_ID",
        "drug": "$RX_DRUG_ESCAPED",
        "dosage": "$RX_DOSAGE_ESCAPED",
        "quantity": "$RX_QUANTITY",
        "refills": "$RX_REFILLS",
        "date_added": "$RX_DATE_ADDED",
        "modified_timestamp": "$RX_MODIFIED_TS"
    },
    "validation": {
        "drug_contains_amlodipine": $DRUG_VALID,
        "quantity_valid": $QUANTITY_VALID,
        "refills_valid": $REFILLS_VALID,
        "date_valid": $DATE_VALID
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/renew_prescription_result.json 2>/dev/null || sudo rm -f /tmp/renew_prescription_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/renew_prescription_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/renew_prescription_result.json
chmod 666 /tmp/renew_prescription_result.json 2>/dev/null || sudo chmod 666 /tmp/renew_prescription_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/renew_prescription_result.json"
cat /tmp/renew_prescription_result.json

echo ""
echo "=== Export Complete ==="