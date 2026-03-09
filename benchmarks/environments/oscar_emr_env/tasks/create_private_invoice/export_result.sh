#!/bin/bash
# Export script for Create Private Invoice task
# Exports details of the most recently created bill for Maria Santos

echo "=== Exporting Invoice Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get Task Metadata
PATIENT_NO=$(cat /tmp/task_patient_no 2>/dev/null || echo "")
INITIAL_MAX_ID=$(cat /tmp/initial_max_bill_id 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Checking for bills created for demographic_no=$PATIENT_NO after ID=$INITIAL_MAX_ID..."

# Query the most recent bill for this patient that was created during the task
# billing_master table usually holds the header info
# We check for bills with ID > Initial Max
BILL_QUERY="SELECT billing_no, total_bill_amount, billing_type, dx_code1, billing_date 
            FROM billing_master 
            WHERE demographic_no='$PATIENT_NO' 
            AND billing_no > $INITIAL_MAX_ID 
            ORDER BY billing_no DESC LIMIT 1"

BILL_DATA=$(oscar_query "$BILL_QUERY")

# Initialize variables
BILL_FOUND="false"
BILL_ID=""
AMOUNT="0.00"
BILL_TYPE=""
DIAGNOSIS=""
BILL_DATE=""

if [ -n "$BILL_DATA" ]; then
    BILL_FOUND="true"
    # Parse tab-separated values
    BILL_ID=$(echo "$BILL_DATA" | cut -f1)
    AMOUNT=$(echo "$BILL_DATA" | cut -f2)
    BILL_TYPE=$(echo "$BILL_DATA" | cut -f3)
    DIAGNOSIS=$(echo "$BILL_DATA" | cut -f4)
    BILL_DATE=$(echo "$BILL_DATA" | cut -f5)
    
    echo "Found Bill #$BILL_ID: Amount=$AMOUNT, Type=$BILL_TYPE, Dx=$DIAGNOSIS"
else
    echo "No new bill found for patient."
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/invoice_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bill_found": $BILL_FOUND,
    "bill_id": "${BILL_ID}",
    "amount": "${AMOUNT}",
    "bill_type": "${BILL_TYPE}",
    "diagnosis": "${DIAGNOSIS}",
    "bill_date": "${BILL_DATE}",
    "patient_id": "${PATIENT_NO}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="