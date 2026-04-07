#!/bin/bash
# Export script for Post Account Write-off Task

echo "=== Exporting Post Account Write-off Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Target patient
PATIENT_PID=3

# Get initial counts
INITIAL_AR_COUNT=$(cat /tmp/initial_ar_count.txt 2>/dev/null || echo "0")
INITIAL_SESSION_COUNT=$(cat /tmp/initial_session_count.txt 2>/dev/null || echo "0")
INITIAL_PAYMENTS_COUNT=$(cat /tmp/initial_payments_count.txt 2>/dev/null || echo "0")
INITIAL_AR_MAX_SEQ=$(cat /tmp/initial_ar_max_seq.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_AR_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_SESSION_COUNT=$(openemr_query "SELECT COUNT(*) FROM ar_session WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_PAYMENTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM payments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo ""
echo "Count comparison:"
echo "  ar_activity: $INITIAL_AR_COUNT -> $CURRENT_AR_COUNT"
echo "  ar_session: $INITIAL_SESSION_COUNT -> $CURRENT_SESSION_COUNT"
echo "  payments: $INITIAL_PAYMENTS_COUNT -> $CURRENT_PAYMENTS_COUNT"

# Query for new ar_activity entries (adjustments)
echo ""
echo "=== Querying for new ar_activity entries ==="
NEW_AR_ACTIVITY=$(openemr_query "SELECT pid, encounter, code, modifier, payer_type, adj_amount, pay_amount, memo, post_time, post_user, account_code FROM ar_activity WHERE pid=$PATIENT_PID AND sequence_no > $INITIAL_AR_MAX_SEQ ORDER BY sequence_no DESC LIMIT 5" 2>/dev/null)
echo "New ar_activity entries:"
echo "$NEW_AR_ACTIVITY"

# Query for recent ar_session entries
echo ""
echo "=== Querying for recent ar_session entries ==="
RECENT_SESSIONS=$(openemr_query "SELECT session_id, payer_id, user_id, pay_total, created_time, patient_id, adjustment_code, post_to_date, global_amount FROM ar_session WHERE patient_id=$PATIENT_PID ORDER BY session_id DESC LIMIT 5" 2>/dev/null)
echo "Recent ar_session entries:"
echo "$RECENT_SESSIONS"

# Check for adjustments with the expected amount ($15.00)
echo ""
echo "=== Looking for \$15.00 adjustment ==="
MATCHING_ADJUSTMENT=$(openemr_query "SELECT pid, adj_amount, pay_amount, memo, post_time, account_code FROM ar_activity WHERE pid=$PATIENT_PID AND (ABS(adj_amount - 15.00) < 0.01 OR ABS(adj_amount + 15.00) < 0.01 OR ABS(pay_amount - 15.00) < 0.01 OR ABS(pay_amount + 15.00) < 0.01) ORDER BY sequence_no DESC LIMIT 1" 2>/dev/null)
echo "Matching adjustment: $MATCHING_ADJUSTMENT"

# Parse the adjustment data
ADJUSTMENT_FOUND="false"
ADJ_AMOUNT=""
ADJ_MEMO=""
ADJ_POST_TIME=""
ADJ_ACCOUNT_CODE=""

if [ -n "$MATCHING_ADJUSTMENT" ]; then
    ADJUSTMENT_FOUND="true"
    ADJ_PID=$(echo "$MATCHING_ADJUSTMENT" | cut -f1)
    ADJ_AMOUNT=$(echo "$MATCHING_ADJUSTMENT" | cut -f2)
    PAY_AMOUNT=$(echo "$MATCHING_ADJUSTMENT" | cut -f3)
    ADJ_MEMO=$(echo "$MATCHING_ADJUSTMENT" | cut -f4)
    ADJ_POST_TIME=$(echo "$MATCHING_ADJUSTMENT" | cut -f5)
    ADJ_ACCOUNT_CODE=$(echo "$MATCHING_ADJUSTMENT" | cut -f6)
    
    # Use pay_amount if adj_amount is empty
    if [ -z "$ADJ_AMOUNT" ] || [ "$ADJ_AMOUNT" = "0.00" ]; then
        ADJ_AMOUNT="$PAY_AMOUNT"
    fi
    
    echo "Found adjustment:"
    echo "  PID: $ADJ_PID"
    echo "  Amount: $ADJ_AMOUNT"
    echo "  Memo: $ADJ_MEMO"
    echo "  Post Time: $ADJ_POST_TIME"
    echo "  Account Code: $ADJ_ACCOUNT_CODE"
fi

# Also check if any new transaction exists (even without exact amount match)
NEW_TRANSACTION_EXISTS="false"
if [ "$CURRENT_AR_COUNT" -gt "$INITIAL_AR_COUNT" ] || [ "$CURRENT_SESSION_COUNT" -gt "$INITIAL_SESSION_COUNT" ]; then
    NEW_TRANSACTION_EXISTS="true"
    echo "New transaction detected (count increased)"
fi

# Check for any recent billing entries
echo ""
echo "=== Checking billing table ==="
RECENT_BILLING=$(openemr_query "SELECT id, date, code_type, code, modifier, pid, user, bill_date, process_date FROM billing WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent billing entries:"
echo "$RECENT_BILLING"

# Escape special characters for JSON
ADJ_MEMO_ESCAPED=$(echo "$ADJ_MEMO" | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\t' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/writeoff_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "initial_counts": {
        "ar_activity": ${INITIAL_AR_COUNT:-0},
        "ar_session": ${INITIAL_SESSION_COUNT:-0},
        "payments": ${INITIAL_PAYMENTS_COUNT:-0},
        "ar_max_seq": ${INITIAL_AR_MAX_SEQ:-0}
    },
    "current_counts": {
        "ar_activity": ${CURRENT_AR_COUNT:-0},
        "ar_session": ${CURRENT_SESSION_COUNT:-0},
        "payments": ${CURRENT_PAYMENTS_COUNT:-0}
    },
    "adjustment_found": $ADJUSTMENT_FOUND,
    "new_transaction_exists": $NEW_TRANSACTION_EXISTS,
    "adjustment": {
        "amount": "$ADJ_AMOUNT",
        "memo": "$ADJ_MEMO_ESCAPED",
        "post_time": "$ADJ_POST_TIME",
        "account_code": "$ADJ_ACCOUNT_CODE"
    },
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/writeoff_result.json 2>/dev/null || sudo rm -f /tmp/writeoff_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/writeoff_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/writeoff_result.json
chmod 666 /tmp/writeoff_result.json 2>/dev/null || sudo chmod 666 /tmp/writeoff_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/writeoff_result.json"
cat /tmp/writeoff_result.json

echo ""
echo "=== Export Complete ==="