#!/bin/bash
echo "=== Exporting Post Patient Refund Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Taking final screenshot..."
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Get target patient info
PATIENT_PID=$(cat /tmp/target_patient_pid.txt 2>/dev/null || echo "0")
PATIENT_FNAME="Marcus"
PATIENT_LNAME="Cartwright"

echo "Checking billing records for patient PID: $PATIENT_PID"

# Get initial counts for comparison
INITIAL_AR_COUNT=$(cat /tmp/initial_ar_count.txt 2>/dev/null || echo "0")
INITIAL_PAY_COUNT=$(cat /tmp/initial_pay_count.txt 2>/dev/null || echo "0")
LATEST_AR_ID=$(cat /tmp/latest_ar_id.txt 2>/dev/null || echo "0")
LATEST_PAY_ID=$(cat /tmp/latest_pay_id.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_AR_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_PAY_COUNT=$(openemr_query "SELECT COUNT(*) FROM payments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "AR activity count: initial=$INITIAL_AR_COUNT, current=$CURRENT_AR_COUNT"
echo "Payments count: initial=$INITIAL_PAY_COUNT, current=$CURRENT_PAY_COUNT"

# Check for new entries in ar_activity table
echo ""
echo "=== Checking ar_activity for refunds ==="
AR_REFUNDS=$(openemr_query "SELECT sequence_no, pid, pay_amount, adj_amount, memo, UNIX_TIMESTAMP(post_time) as post_ts FROM ar_activity WHERE pid=$PATIENT_PID AND sequence_no > $LATEST_AR_ID ORDER BY sequence_no DESC LIMIT 5" 2>/dev/null || echo "")
echo "New AR entries: $AR_REFUNDS"

# Check for new entries in payments table
echo ""
echo "=== Checking payments table for refunds ==="
PAY_REFUNDS=$(openemr_query "SELECT id, pid, dtime, encounter, method, source, amount, memo FROM payments WHERE pid=$PATIENT_PID AND id > $LATEST_PAY_ID ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "")
echo "New payment entries: $PAY_REFUNDS"

# Also check all recent ar_activity entries for negative amounts
echo ""
echo "=== All recent AR entries with negative amounts ==="
ALL_AR_NEGATIVE=$(openemr_query "SELECT sequence_no, pid, pay_amount, adj_amount, memo, UNIX_TIMESTAMP(post_time) as post_ts FROM ar_activity WHERE (pay_amount < 0 OR adj_amount < 0) AND post_time > FROM_UNIXTIME($TASK_START) ORDER BY sequence_no DESC LIMIT 10" 2>/dev/null || echo "")
echo "Negative AR entries since task start: $ALL_AR_NEGATIVE"

# Check all recent payments with negative amounts
echo ""
echo "=== All recent payments with negative amounts ==="
ALL_PAY_NEGATIVE=$(openemr_query "SELECT id, pid, dtime, amount, memo, source FROM payments WHERE amount < 0 ORDER BY id DESC LIMIT 10" 2>/dev/null || echo "")
echo "Negative payment entries: $ALL_PAY_NEGATIVE"

# Parse the results to find refund data
REFUND_FOUND="false"
REFUND_AMOUNT="0"
REFUND_MEMO=""
REFUND_SOURCE=""
REFUND_TIMESTAMP="0"
REFUND_FROM_AR="false"
REFUND_FROM_PAY="false"

# First check ar_activity for new negative entries
if [ -n "$AR_REFUNDS" ]; then
    while IFS=$'\t' read -r seq_no ar_pid pay_amt adj_amt memo post_ts; do
        # Skip header or empty lines
        [ -z "$seq_no" ] && continue
        
        # Check for negative pay_amount or adj_amount
        if [ -n "$pay_amt" ] && [ "$pay_amt" != "0.00" ] && [ "$pay_amt" != "0" ]; then
            # Check if negative (starts with -)
            if [[ "$pay_amt" == -* ]]; then
                REFUND_FOUND="true"
                REFUND_FROM_AR="true"
                REFUND_AMOUNT="$pay_amt"
                REFUND_MEMO="$memo"
                REFUND_TIMESTAMP="$post_ts"
                echo "Found refund in ar_activity: amount=$pay_amt, memo=$memo"
                break
            fi
        fi
        if [ -n "$adj_amt" ] && [ "$adj_amt" != "0.00" ] && [ "$adj_amt" != "0" ]; then
            if [[ "$adj_amt" == -* ]]; then
                REFUND_FOUND="true"
                REFUND_FROM_AR="true"
                REFUND_AMOUNT="$adj_amt"
                REFUND_MEMO="$memo"
                REFUND_TIMESTAMP="$post_ts"
                echo "Found refund adjustment in ar_activity: amount=$adj_amt, memo=$memo"
                break
            fi
        fi
    done <<< "$AR_REFUNDS"
fi

# Then check payments table if not found in ar_activity
if [ "$REFUND_FOUND" = "false" ] && [ -n "$PAY_REFUNDS" ]; then
    while IFS=$'\t' read -r pay_id pay_pid pay_dtime pay_enc pay_method pay_source pay_amount pay_memo; do
        [ -z "$pay_id" ] && continue
        
        if [ -n "$pay_amount" ] && [[ "$pay_amount" == -* ]]; then
            REFUND_FOUND="true"
            REFUND_FROM_PAY="true"
            REFUND_AMOUNT="$pay_amount"
            REFUND_MEMO="$pay_memo"
            REFUND_SOURCE="$pay_source"
            echo "Found refund in payments: amount=$pay_amount, memo=$pay_memo, source=$pay_source"
            break
        fi
    done <<< "$PAY_REFUNDS"
fi

# Check if amount is close to expected -45.00
AMOUNT_CORRECT="false"
if [ "$REFUND_FOUND" = "true" ]; then
    # Remove minus sign for comparison
    ABS_AMOUNT=$(echo "$REFUND_AMOUNT" | tr -d '-')
    # Check if between 44 and 46
    if (( $(echo "$ABS_AMOUNT >= 44 && $ABS_AMOUNT <= 46" | bc -l 2>/dev/null || echo "0") )); then
        AMOUNT_CORRECT="true"
        echo "Amount is correct (within tolerance): $REFUND_AMOUNT"
    else
        echo "Amount outside expected range: $REFUND_AMOUNT (expected ~-45.00)"
    fi
fi

# Check if memo contains required keywords
DOCUMENTATION_VALID="false"
MEMO_LOWER=$(echo "$REFUND_MEMO $REFUND_SOURCE" | tr '[:upper:]' '[:lower:]')
if echo "$MEMO_LOWER" | grep -qE "(overpay|refund|credit|balance|insurance)"; then
    DOCUMENTATION_VALID="true"
    echo "Documentation contains expected keywords"
fi

# Check timestamp validity
TIMESTAMP_VALID="false"
if [ "$REFUND_TIMESTAMP" -gt "$TASK_START" ] 2>/dev/null; then
    TIMESTAMP_VALID="true"
    echo "Refund timestamp is valid (created after task start)"
fi

# Also check if new records were created based on count change
NEW_RECORDS_CREATED="false"
if [ "$CURRENT_AR_COUNT" -gt "$INITIAL_AR_COUNT" ] || [ "$CURRENT_PAY_COUNT" -gt "$INITIAL_PAY_COUNT" ]; then
    NEW_RECORDS_CREATED="true"
fi

# Escape special characters for JSON
REFUND_MEMO_ESCAPED=$(echo "$REFUND_MEMO" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 200)
REFUND_SOURCE_ESCAPED=$(echo "$REFUND_SOURCE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/refund_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "patient": {
        "pid": $PATIENT_PID,
        "fname": "$PATIENT_FNAME",
        "lname": "$PATIENT_LNAME"
    },
    "counts": {
        "initial_ar_count": $INITIAL_AR_COUNT,
        "current_ar_count": $CURRENT_AR_COUNT,
        "initial_pay_count": $INITIAL_PAY_COUNT,
        "current_pay_count": $CURRENT_PAY_COUNT,
        "new_records_created": $NEW_RECORDS_CREATED
    },
    "refund": {
        "found": $REFUND_FOUND,
        "amount": "$REFUND_AMOUNT",
        "memo": "$REFUND_MEMO_ESCAPED",
        "source": "$REFUND_SOURCE_ESCAPED",
        "timestamp": $REFUND_TIMESTAMP,
        "from_ar_activity": $REFUND_FROM_AR,
        "from_payments": $REFUND_FROM_PAY
    },
    "validation": {
        "amount_correct": $AMOUNT_CORRECT,
        "documentation_valid": $DOCUMENTATION_VALID,
        "timestamp_valid": $TIMESTAMP_VALID
    },
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/post_refund_result.json 2>/dev/null || sudo rm -f /tmp/post_refund_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/post_refund_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/post_refund_result.json
chmod 666 /tmp/post_refund_result.json 2>/dev/null || sudo chmod 666 /tmp/post_refund_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/post_refund_result.json"
cat /tmp/post_refund_result.json
echo ""
echo "=== Export Complete ==="