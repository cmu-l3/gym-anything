#!/bin/bash
# Export script for Write Prescription Task

echo "=== Exporting Write Prescription Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Target patient
PATIENT_PID=1

# Get initial counts from setup
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count 2>/dev/null || echo "0")
INITIAL_TOTAL_RX=$(cat /tmp/initial_total_rx_count 2>/dev/null || echo "0")
EXISTING_RX_IDS=$(cat /tmp/existing_rx_ids 2>/dev/null || echo "")

# Get current prescription count for patient
CURRENT_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL_RX=$(openemr_query "SELECT COUNT(*) FROM prescriptions" 2>/dev/null || echo "0")

echo "Prescription count: initial=$INITIAL_RX_COUNT, current=$CURRENT_RX_COUNT"
echo "Total RX: initial=$INITIAL_TOTAL_RX, current=$CURRENT_TOTAL_RX"

# Debug: Show all prescriptions for this patient
echo ""
echo "=== DEBUG: All prescriptions for patient PID=$PATIENT_PID ==="
openemr_query "SELECT id, drug, dosage, quantity, refills, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Find new prescriptions (IDs that didn't exist before)
echo "Looking for new prescriptions..."
if [ -n "$EXISTING_RX_IDS" ]; then
    NEW_RX_QUERY="SELECT id, drug, dosage, quantity, size, unit, route, form, refills, note, date_added, active FROM prescriptions WHERE patient_id=$PATIENT_PID AND id NOT IN ($EXISTING_RX_IDS) ORDER BY id DESC LIMIT 5"
else
    NEW_RX_QUERY="SELECT id, drug, dosage, quantity, size, unit, route, form, refills, note, date_added, active FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 5"
fi

NEW_RX_DATA=$(openemr_query "$NEW_RX_QUERY" 2>/dev/null)

# Also specifically look for Ciprofloxacin prescriptions
CIPRO_RX=$(openemr_query "SELECT id, drug, dosage, quantity, refills, date_added, active FROM prescriptions WHERE patient_id=$PATIENT_PID AND (drug LIKE '%Ciprofloxacin%' OR drug LIKE '%ciprofloxacin%' OR drug LIKE '%CIPROFLOXACIN%' OR drug LIKE '%cipro%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse the newest prescription data
RX_FOUND="false"
RX_ID=""
RX_DRUG=""
RX_DOSAGE=""
RX_QUANTITY=""
RX_SIZE=""
RX_UNIT=""
RX_ROUTE=""
RX_FORM=""
RX_REFILLS=""
RX_NOTE=""
RX_DATE_ADDED=""
RX_ACTIVE=""
IS_CIPROFLOXACIN="false"
IS_NEW="false"

# First check if we have a Ciprofloxacin prescription
if [ -n "$CIPRO_RX" ]; then
    RX_FOUND="true"
    IS_CIPROFLOXACIN="true"
    RX_ID=$(echo "$CIPRO_RX" | cut -f1)
    RX_DRUG=$(echo "$CIPRO_RX" | cut -f2)
    RX_DOSAGE=$(echo "$CIPRO_RX" | cut -f3)
    RX_QUANTITY=$(echo "$CIPRO_RX" | cut -f4)
    RX_REFILLS=$(echo "$CIPRO_RX" | cut -f5)
    RX_DATE_ADDED=$(echo "$CIPRO_RX" | cut -f6)
    RX_ACTIVE=$(echo "$CIPRO_RX" | cut -f7)
    
    echo "Ciprofloxacin prescription found: ID=$RX_ID, Drug='$RX_DRUG'"
    
    # Check if this is a new prescription (ID not in existing list)
    if [ -n "$EXISTING_RX_IDS" ]; then
        if ! echo ",$EXISTING_RX_IDS," | grep -q ",$RX_ID,"; then
            IS_NEW="true"
            echo "This is a NEW prescription (ID=$RX_ID not in existing: $EXISTING_RX_IDS)"
        else
            echo "WARNING: This prescription existed before task started"
        fi
    else
        # No existing prescriptions, so any found is new
        IS_NEW="true"
    fi
elif [ -n "$NEW_RX_DATA" ]; then
    # Fall back to any new prescription
    RX_FOUND="true"
    IS_NEW="true"
    RX_ID=$(echo "$NEW_RX_DATA" | head -1 | cut -f1)
    RX_DRUG=$(echo "$NEW_RX_DATA" | head -1 | cut -f2)
    RX_DOSAGE=$(echo "$NEW_RX_DATA" | head -1 | cut -f3)
    RX_QUANTITY=$(echo "$NEW_RX_DATA" | head -1 | cut -f4)
    RX_SIZE=$(echo "$NEW_RX_DATA" | head -1 | cut -f5)
    RX_UNIT=$(echo "$NEW_RX_DATA" | head -1 | cut -f6)
    RX_ROUTE=$(echo "$NEW_RX_DATA" | head -1 | cut -f7)
    RX_FORM=$(echo "$NEW_RX_DATA" | head -1 | cut -f8)
    RX_REFILLS=$(echo "$NEW_RX_DATA" | head -1 | cut -f9)
    RX_NOTE=$(echo "$NEW_RX_DATA" | head -1 | cut -f10)
    RX_DATE_ADDED=$(echo "$NEW_RX_DATA" | head -1 | cut -f11)
    RX_ACTIVE=$(echo "$NEW_RX_DATA" | head -1 | cut -f12)
    
    # Check if it's ciprofloxacin
    if echo "$RX_DRUG" | grep -qi "cipro"; then
        IS_CIPROFLOXACIN="true"
    fi
    
    echo "New prescription found: ID=$RX_ID, Drug='$RX_DRUG'"
else
    echo "No prescription found for patient"
fi

# Validate quantity
QUANTITY_VALID="false"
if [ -n "$RX_QUANTITY" ]; then
    # Try to extract numeric value
    QUANTITY_NUM=$(echo "$RX_QUANTITY" | grep -oE '[0-9]+' | head -1)
    if [ -n "$QUANTITY_NUM" ] && [ "$QUANTITY_NUM" -gt 0 ]; then
        QUANTITY_VALID="true"
        echo "Quantity is valid: $QUANTITY_NUM"
    fi
fi

# Check timestamp validity (prescription should be created after task start)
TIMESTAMP_VALID="false"
if [ -n "$RX_DATE_ADDED" ]; then
    # Convert date to epoch if possible
    RX_EPOCH=$(date -d "$RX_DATE_ADDED" +%s 2>/dev/null || echo "0")
    # Give some buffer (prescription could be dated slightly before due to timezone/rounding)
    BUFFER_START=$((TASK_START - 300))  # 5 minutes buffer
    if [ "$RX_EPOCH" -ge "$BUFFER_START" ]; then
        TIMESTAMP_VALID="true"
        echo "Timestamp valid: $RX_DATE_ADDED (epoch: $RX_EPOCH >= $BUFFER_START)"
    else
        echo "Timestamp may be invalid: $RX_DATE_ADDED (epoch: $RX_EPOCH < $BUFFER_START)"
    fi
fi

# Escape special characters for JSON
RX_DRUG_ESCAPED=$(echo "$RX_DRUG" | sed 's/"/\\"/g' | tr '\n' ' ')
RX_DOSAGE_ESCAPED=$(echo "$RX_DOSAGE" | sed 's/"/\\"/g' | tr '\n' ' ')
RX_NOTE_ESCAPED=$(echo "$RX_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/rx_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "initial_rx_count": ${INITIAL_RX_COUNT:-0},
    "current_rx_count": ${CURRENT_RX_COUNT:-0},
    "initial_total_rx": ${INITIAL_TOTAL_RX:-0},
    "current_total_rx": ${CURRENT_TOTAL_RX:-0},
    "prescription_found": $RX_FOUND,
    "is_ciprofloxacin": $IS_CIPROFLOXACIN,
    "is_new_prescription": $IS_NEW,
    "quantity_valid": $QUANTITY_VALID,
    "timestamp_valid": $TIMESTAMP_VALID,
    "prescription": {
        "id": "$RX_ID",
        "drug": "$RX_DRUG_ESCAPED",
        "dosage": "$RX_DOSAGE_ESCAPED",
        "quantity": "$RX_QUANTITY",
        "size": "$RX_SIZE",
        "unit": "$RX_UNIT",
        "route": "$RX_ROUTE",
        "form": "$RX_FORM",
        "refills": "$RX_REFILLS",
        "note": "$RX_NOTE_ESCAPED",
        "date_added": "$RX_DATE_ADDED",
        "active": "$RX_ACTIVE"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/write_prescription_result.json 2>/dev/null || sudo rm -f /tmp/write_prescription_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/write_prescription_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/write_prescription_result.json
chmod 666 /tmp/write_prescription_result.json 2>/dev/null || sudo chmod 666 /tmp/write_prescription_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/write_prescription_result.json"
cat /tmp/write_prescription_result.json

echo ""
echo "=== Export Complete ==="