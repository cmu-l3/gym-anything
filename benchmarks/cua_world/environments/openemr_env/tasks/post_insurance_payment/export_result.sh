#!/bin/bash
# Export script for Post Insurance Payment Task

echo "=== Exporting Post Insurance Payment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Target patient
PATIENT_PID=3

# Get timestamps and initial counts
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_AR_COUNT=$(cat /tmp/initial_ar_count 2>/dev/null || echo "0")
INITIAL_PAYMENTS=$(cat /tmp/initial_payments_total 2>/dev/null || echo "0")
ENCOUNTER_ID=$(cat /tmp/task_encounter_id 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get current ar_activity count for patient
CURRENT_AR_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "ar_activity count: initial=$INITIAL_AR_COUNT, current=$CURRENT_AR_COUNT"

# Get current total payments
CURRENT_PAYMENTS=$(openemr_query "SELECT COALESCE(SUM(pay_amount), 0) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Total payments: initial=$INITIAL_PAYMENTS, current=$CURRENT_PAYMENTS"

# Query for ALL recent payment records for this patient
echo ""
echo "=== Querying ar_activity for patient PID=$PATIENT_PID ==="
ALL_AR_ACTIVITY=$(openemr_query "SELECT sequence_no, encounter, code_type, code, payer_type, pay_amount, adj_amount, memo, post_time FROM ar_activity WHERE pid=$PATIENT_PID ORDER BY sequence_no DESC LIMIT 10" 2>/dev/null)
echo "Recent ar_activity records:"
echo "$ALL_AR_ACTIVITY"

# Find the newest payment record (highest sequence_no with pay_amount > 0)
NEWEST_PAYMENT=$(openemr_query "SELECT sequence_no, encounter, code_type, code, payer_type, pay_amount, adj_amount, memo, post_time FROM ar_activity WHERE pid=$PATIENT_PID AND pay_amount > 0 ORDER BY sequence_no DESC LIMIT 1" 2>/dev/null)

# Parse payment data
PAYMENT_FOUND="false"
PAYMENT_SEQNO=""
PAYMENT_ENCOUNTER=""
PAYMENT_CODE_TYPE=""
PAYMENT_CODE=""
PAYMENT_PAYER_TYPE=""
PAYMENT_AMOUNT="0"
PAYMENT_ADJ_AMOUNT="0"
PAYMENT_MEMO=""
PAYMENT_POST_TIME=""

if [ -n "$NEWEST_PAYMENT" ] && [ "$CURRENT_AR_COUNT" -gt "$INITIAL_AR_COUNT" ]; then
    PAYMENT_FOUND="true"
    PAYMENT_SEQNO=$(echo "$NEWEST_PAYMENT" | cut -f1)
    PAYMENT_ENCOUNTER=$(echo "$NEWEST_PAYMENT" | cut -f2)
    PAYMENT_CODE_TYPE=$(echo "$NEWEST_PAYMENT" | cut -f3)
    PAYMENT_CODE=$(echo "$NEWEST_PAYMENT" | cut -f4)
    PAYMENT_PAYER_TYPE=$(echo "$NEWEST_PAYMENT" | cut -f5)
    PAYMENT_AMOUNT=$(echo "$NEWEST_PAYMENT" | cut -f6)
    PAYMENT_ADJ_AMOUNT=$(echo "$NEWEST_PAYMENT" | cut -f7)
    PAYMENT_MEMO=$(echo "$NEWEST_PAYMENT" | cut -f8)
    PAYMENT_POST_TIME=$(echo "$NEWEST_PAYMENT" | cut -f9)

    echo ""
    echo "New payment found:"
    echo "  Sequence: $PAYMENT_SEQNO"
    echo "  Encounter: $PAYMENT_ENCOUNTER"
    echo "  Payer Type: $PAYMENT_PAYER_TYPE (0=patient, 1=primary ins, 2=secondary, 3=tertiary)"
    echo "  Payment Amount: \$$PAYMENT_AMOUNT"
    echo "  Adjustment Amount: \$$PAYMENT_ADJ_AMOUNT"
    echo "  Memo/Reference: $PAYMENT_MEMO"
    echo "  Post Time: $PAYMENT_POST_TIME"
else
    echo "No new payment records found for patient"
fi

# Also check the payments table (some OpenEMR versions use this)
echo ""
echo "=== Checking payments table ==="
PAYMENTS_TABLE=$(openemr_query "SELECT id, pid, dtime, encounter, source, amount, method FROM payments WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Payments table records:"
echo "$PAYMENTS_TABLE"

# Check for adjustment-only records (separate from payment)
NEWEST_ADJUSTMENT=$(openemr_query "SELECT sequence_no, encounter, adj_amount, memo, post_time FROM ar_activity WHERE pid=$PATIENT_PID AND adj_amount > 0 ORDER BY sequence_no DESC LIMIT 1" 2>/dev/null)
ADJ_FOUND="false"
ADJ_AMOUNT_SEPARATE="0"
if [ -n "$NEWEST_ADJUSTMENT" ]; then
    ADJ_FOUND="true"
    ADJ_AMOUNT_SEPARATE=$(echo "$NEWEST_ADJUSTMENT" | cut -f3)
    echo ""
    echo "Adjustment record found: \$$ADJ_AMOUNT_SEPARATE"
fi

# Check if reference number is present anywhere
REFERENCE_FOUND="false"
REFERENCE_LOWER=$(echo "$PAYMENT_MEMO" | tr '[:upper:]' '[:lower:]')
if echo "$REFERENCE_LOWER" | grep -qE "(eob|2024|7834|eob2024)"; then
    REFERENCE_FOUND="true"
    echo "Reference number found in memo"
fi

# Check payer type (1=insurance primary, 2=secondary, 3=tertiary; 0=patient)
PAYER_IS_INSURANCE="false"
if [ "$PAYMENT_PAYER_TYPE" = "1" ] || [ "$PAYMENT_PAYER_TYPE" = "2" ] || [ "$PAYMENT_PAYER_TYPE" = "3" ]; then
    PAYER_IS_INSURANCE="true"
    echo "Payment marked as insurance payment"
elif [ "$PAYMENT_PAYER_TYPE" = "0" ]; then
    echo "Payment marked as patient payment (expected insurance)"
fi

# Escape special characters for JSON
PAYMENT_MEMO_ESCAPED=$(echo "$PAYMENT_MEMO" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/insurance_payment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "encounter_id": "$ENCOUNTER_ID",
    "initial_ar_count": ${INITIAL_AR_COUNT:-0},
    "current_ar_count": ${CURRENT_AR_COUNT:-0},
    "initial_payments_total": ${INITIAL_PAYMENTS:-0},
    "current_payments_total": ${CURRENT_PAYMENTS:-0},
    "new_payment_found": $PAYMENT_FOUND,
    "payment": {
        "sequence_no": "$PAYMENT_SEQNO",
        "encounter": "$PAYMENT_ENCOUNTER",
        "code_type": "$PAYMENT_CODE_TYPE",
        "code": "$PAYMENT_CODE",
        "payer_type": "$PAYMENT_PAYER_TYPE",
        "amount": ${PAYMENT_AMOUNT:-0},
        "adjustment_amount": ${PAYMENT_ADJ_AMOUNT:-0},
        "memo": "$PAYMENT_MEMO_ESCAPED",
        "post_time": "$PAYMENT_POST_TIME"
    },
    "validation": {
        "reference_found": $REFERENCE_FOUND,
        "payer_is_insurance": $PAYER_IS_INSURANCE,
        "adjustment_found": $ADJ_FOUND,
        "adjustment_amount_separate": ${ADJ_AMOUNT_SEPARATE:-0}
    },
    "screenshot_final": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result to expected location
rm -f /tmp/insurance_payment_result.json 2>/dev/null || sudo rm -f /tmp/insurance_payment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/insurance_payment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/insurance_payment_result.json
chmod 666 /tmp/insurance_payment_result.json 2>/dev/null || sudo chmod 666 /tmp/insurance_payment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/insurance_payment_result.json"
cat /tmp/insurance_payment_result.json

echo ""
echo "=== Export Complete ==="