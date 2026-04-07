#!/bin/bash
# Export script for Prescribe Medication Task

echo "=== Exporting Prescribe Medication Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target patient
PATIENT_PID=7

# Get initial counts
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current prescription count for patient
CURRENT_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Prescription count: initial=$INITIAL_RX_COUNT, current=$CURRENT_RX_COUNT"

# Query for all recent prescriptions for this patient
echo ""
echo "=== Querying prescriptions for patient PID=$PATIENT_PID ==="
ALL_RX=$(openemr_query "SELECT id, drug, dosage, quantity, unit, refills, active, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "All prescriptions for patient:"
echo "$ALL_RX"

# Find the most recent amoxicillin prescription
NEWEST_AMOX=$(openemr_query "SELECT id, drug, dosage, quantity, unit, form, route, refills, active, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID AND LOWER(drug) LIKE '%amoxicillin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Also find any new prescription (not just amoxicillin)
NEWEST_ANY=$(openemr_query "SELECT id, drug, dosage, quantity, unit, form, route, refills, active, date_added FROM prescriptions WHERE patient_id=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse prescription data
RX_FOUND="false"
RX_ID=""
RX_DRUG=""
RX_DOSAGE=""
RX_QUANTITY=""
RX_UNIT=""
RX_FORM=""
RX_ROUTE=""
RX_REFILLS=""
RX_ACTIVE=""
RX_DATE=""

# Prefer amoxicillin if found
if [ -n "$NEWEST_AMOX" ]; then
    RX_FOUND="true"
    RX_ID=$(echo "$NEWEST_AMOX" | cut -f1)
    RX_DRUG=$(echo "$NEWEST_AMOX" | cut -f2)
    RX_DOSAGE=$(echo "$NEWEST_AMOX" | cut -f3)
    RX_QUANTITY=$(echo "$NEWEST_AMOX" | cut -f4)
    RX_UNIT=$(echo "$NEWEST_AMOX" | cut -f5)
    RX_FORM=$(echo "$NEWEST_AMOX" | cut -f6)
    RX_ROUTE=$(echo "$NEWEST_AMOX" | cut -f7)
    RX_REFILLS=$(echo "$NEWEST_AMOX" | cut -f8)
    RX_ACTIVE=$(echo "$NEWEST_AMOX" | cut -f9)
    RX_DATE=$(echo "$NEWEST_AMOX" | cut -f10)

    echo ""
    echo "Amoxicillin prescription found:"
    echo "  ID: $RX_ID"
    echo "  Drug: $RX_DRUG"
    echo "  Dosage: $RX_DOSAGE"
    echo "  Quantity: $RX_QUANTITY"
    echo "  Unit: $RX_UNIT"
    echo "  Form: $RX_FORM"
    echo "  Refills: $RX_REFILLS"
    echo "  Active: $RX_ACTIVE"
    echo "  Date: $RX_DATE"
elif [ -n "$NEWEST_ANY" ] && [ "$CURRENT_RX_COUNT" -gt "$INITIAL_RX_COUNT" ]; then
    # New prescription exists but not amoxicillin
    RX_FOUND="true"
    RX_ID=$(echo "$NEWEST_ANY" | cut -f1)
    RX_DRUG=$(echo "$NEWEST_ANY" | cut -f2)
    RX_DOSAGE=$(echo "$NEWEST_ANY" | cut -f3)
    RX_QUANTITY=$(echo "$NEWEST_ANY" | cut -f4)
    RX_UNIT=$(echo "$NEWEST_ANY" | cut -f5)
    RX_FORM=$(echo "$NEWEST_ANY" | cut -f6)
    RX_ROUTE=$(echo "$NEWEST_ANY" | cut -f7)
    RX_REFILLS=$(echo "$NEWEST_ANY" | cut -f8)
    RX_ACTIVE=$(echo "$NEWEST_ANY" | cut -f9)
    RX_DATE=$(echo "$NEWEST_ANY" | cut -f10)

    echo ""
    echo "Non-amoxicillin prescription found:"
    echo "  Drug: $RX_DRUG"
else
    echo "No new prescription found for patient"
fi

# Check if this is a new prescription (id > initial max id or count increased)
IS_NEW="false"
if [ "$CURRENT_RX_COUNT" -gt "$INITIAL_RX_COUNT" ]; then
    IS_NEW="true"
fi

# Check if drug is amoxicillin
IS_AMOXICILLIN="false"
DRUG_LOWER=$(echo "$RX_DRUG" | tr '[:upper:]' '[:lower:]')
if echo "$DRUG_LOWER" | grep -q "amoxicillin"; then
    IS_AMOXICILLIN="true"
fi

# Check if quantity is appropriate (20-40 for 10-day course)
QUANTITY_VALID="false"
if [ -n "$RX_QUANTITY" ] && [ "$RX_QUANTITY" -ge 20 ] 2>/dev/null && [ "$RX_QUANTITY" -le 40 ] 2>/dev/null; then
    QUANTITY_VALID="true"
fi

# Check if dosage contains 500
HAS_500MG="false"
if echo "$RX_DRUG $RX_DOSAGE" | grep -q "500"; then
    HAS_500MG="true"
fi

# Escape special characters for JSON
RX_DRUG_ESCAPED=$(echo "$RX_DRUG" | sed 's/"/\\"/g' | tr '\n' ' ')
RX_DOSAGE_ESCAPED=$(echo "$RX_DOSAGE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/prescribe_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "initial_rx_count": ${INITIAL_RX_COUNT:-0},
    "current_rx_count": ${CURRENT_RX_COUNT:-0},
    "prescription_found": $RX_FOUND,
    "prescription": {
        "id": "$RX_ID",
        "drug": "$RX_DRUG_ESCAPED",
        "dosage": "$RX_DOSAGE_ESCAPED",
        "quantity": "${RX_QUANTITY:-0}",
        "unit": "$RX_UNIT",
        "form": "$RX_FORM",
        "route": "$RX_ROUTE",
        "refills": "${RX_REFILLS:-0}",
        "active": "$RX_ACTIVE",
        "date_added": "$RX_DATE"
    },
    "validation": {
        "is_new_prescription": $IS_NEW,
        "is_amoxicillin": $IS_AMOXICILLIN,
        "has_500mg": $HAS_500MG,
        "quantity_appropriate": $QUANTITY_VALID
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/prescribe_medication_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/prescribe_medication_result.json
chmod 666 /tmp/prescribe_medication_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/prescribe_medication_result.json"
cat /tmp/prescribe_medication_result.json

echo ""
echo "=== Export Complete ==="
