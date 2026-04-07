#!/bin/bash
echo "=== Exporting Add Prescription Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_prescription_end.png

# Load context variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PAT_ID=$(cat /tmp/target_patient_id.txt 2>/dev/null)
INITIAL_RX_COUNT=$(cat /tmp/initial_rx_count.txt 2>/dev/null || echo "0")

# Get current prescription count
CURRENT_RX_COUNT=$(freemed_query "SELECT COUNT(*) FROM rx WHERE rxpatient='$PAT_ID'" 2>/dev/null || echo "0")
echo "Prescription count: initial=$INITIAL_RX_COUNT, current=$CURRENT_RX_COUNT"

# Check if a new Lisinopril prescription was added for Margaret Thompson
RX_DATA=$(freemed_query "SELECT rxdrug, rxquantity, rxrefills, rxdosage, rxnote FROM rx WHERE rxpatient='$PAT_ID' ORDER BY id DESC LIMIT 1" 2>/dev/null)

RX_FOUND="false"
RX_DRUG=""
RX_QUANTITY=""
RX_REFILLS=""
RX_DOSAGE=""
RX_NOTE=""

if [ -n "$RX_DATA" ] && [ "$CURRENT_RX_COUNT" -gt "$INITIAL_RX_COUNT" ]; then
    RX_FOUND="true"
    # Parse tab-separated values
    RX_DRUG=$(echo "$RX_DATA" | cut -f1)
    RX_QUANTITY=$(echo "$RX_DATA" | cut -f2)
    RX_REFILLS=$(echo "$RX_DATA" | cut -f3)
    RX_DOSAGE=$(echo "$RX_DATA" | cut -f4)
    RX_NOTE=$(echo "$RX_DATA" | cut -f5)
    
    echo "Latest Prescription found:"
    echo "  Drug: $RX_DRUG"
    echo "  Quantity: $RX_QUANTITY"
    echo "  Refills: $RX_REFILLS"
    echo "  Dosage: $RX_DOSAGE"
    echo "  Note: $RX_NOTE"
else
    echo "No new prescription found for patient ID $PAT_ID."
fi

# Sanitize strings for JSON (escape quotes and backslashes)
RX_DRUG_ESC=$(echo "$RX_DRUG" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n\r')
RX_DOSAGE_ESC=$(echo "$RX_DOSAGE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n\r')
RX_NOTE_ESC=$(echo "$RX_NOTE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n\r')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/rx_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_rx_count": $INITIAL_RX_COUNT,
    "current_rx_count": $CURRENT_RX_COUNT,
    "rx_found": $RX_FOUND,
    "prescription": {
        "drug": "$RX_DRUG_ESC",
        "quantity": "$RX_QUANTITY",
        "refills": "$RX_REFILLS",
        "dosage": "$RX_DOSAGE_ESC",
        "note": "$RX_NOTE_ESC"
    },
    "export_timestamp": "$(date +%s)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="