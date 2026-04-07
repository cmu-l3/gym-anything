#!/bin/bash
# Export script for Record Patient Copay Payment task

echo "=== Exporting Record Patient Copay Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png
sleep 1

# Target patient
PATIENT_PID=4

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $TASK_START to $TASK_END ($(($TASK_END - $TASK_START)) seconds)"

# Get initial counts
INITIAL_PAYMENTS=$(cat /tmp/initial_payments_count.txt 2>/dev/null || echo "0")
INITIAL_AR_ACTIVITY=$(cat /tmp/initial_ar_activity_count.txt 2>/dev/null || echo "0")
INITIAL_AR_SESSION=$(cat /tmp/initial_ar_session_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL=$(cat /tmp/initial_total_payments.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_PAYMENTS=$(openemr_query "SELECT COUNT(*) FROM payments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_AR_ACTIVITY=$(openemr_query "SELECT COUNT(*) FROM ar_activity WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_AR_SESSION=$(openemr_query "SELECT COUNT(*) FROM ar_session WHERE patient_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL=$(openemr_query "SELECT COUNT(*) FROM payments" 2>/dev/null || echo "0")

echo "Payment counts:"
echo "  payments table: $INITIAL_PAYMENTS -> $CURRENT_PAYMENTS"
echo "  ar_activity: $INITIAL_AR_ACTIVITY -> $CURRENT_AR_ACTIVITY"
echo "  ar_session: $INITIAL_AR_SESSION -> $CURRENT_AR_SESSION"
echo "  total payments: $INITIAL_TOTAL -> $CURRENT_TOTAL"

# Initialize result variables
PAYMENT_FOUND="false"
PAYMENT_ID=""
PAYMENT_AMOUNT=""
PAYMENT_METHOD=""
PAYMENT_DATE=""
PAYMENT_NOTE=""
PAYMENT_SOURCE=""

# Convert task start to MySQL datetime format for comparison
TASK_START_DATETIME=$(date -d "@$TASK_START" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "2000-01-01 00:00:00")
echo "Looking for payments created after: $TASK_START_DATETIME"

# Query 1: Check payments table for new payments for this patient
echo ""
echo "=== Checking payments table ==="
PAYMENTS_DATA=$(openemr_query "SELECT id, pid, dtime, amount1, amount2, method, source FROM payments WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent payments for patient:"
echo "$PAYMENTS_DATA"

# Look for the newest payment entry for this patient
NEWEST_PAYMENT=$(openemr_query "SELECT id, pid, dtime, amount1, amount2, method, source FROM payments WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [ -n "$NEWEST_PAYMENT" ] && [ "$CURRENT_PAYMENTS" -gt "$INITIAL_PAYMENTS" ]; then
    echo "Found new payment in payments table"
    PAYMENT_FOUND="true"
    PAYMENT_ID=$(echo "$NEWEST_PAYMENT" | cut -f1)
    PAYMENT_DATE=$(echo "$NEWEST_PAYMENT" | cut -f3)
    PAYMENT_AMOUNT=$(echo "$NEWEST_PAYMENT" | cut -f4)
    PAYMENT_AMOUNT2=$(echo "$NEWEST_PAYMENT" | cut -f5)
    PAYMENT_METHOD=$(echo "$NEWEST_PAYMENT" | cut -f6)
    PAYMENT_SOURCE=$(echo "$NEWEST_PAYMENT" | cut -f7)
    
    # If amount1 is 0, check amount2
    if [ "$PAYMENT_AMOUNT" = "0.00" ] || [ "$PAYMENT_AMOUNT" = "0" ] || [ -z "$PAYMENT_AMOUNT" ]; then
        PAYMENT_AMOUNT="$PAYMENT_AMOUNT2"
    fi
    
    echo "  ID: $PAYMENT_ID"
    echo "  Amount: $PAYMENT_AMOUNT"
    echo "  Method: $PAYMENT_METHOD"
    echo "  Source: $PAYMENT_SOURCE"
    echo "  Date: $PAYMENT_DATE"
fi

# Query 2: Check ar_activity table if no payment found yet
if [ "$PAYMENT_FOUND" = "false" ]; then
    echo ""
    echo "=== Checking ar_activity table ==="
    AR_DATA=$(openemr_query "SELECT pid, encounter, code_type, code, pay_amount, adj_amount, post_time, memo, session_id FROM ar_activity WHERE pid=$PATIENT_PID ORDER BY sequence_no DESC LIMIT 5" 2>/dev/null)
    echo "Recent ar_activity for patient:"
    echo "$AR_DATA"
    
    NEWEST_AR=$(openemr_query "SELECT pid, pay_amount, post_time, memo, session_id FROM ar_activity WHERE pid=$PATIENT_PID AND pay_amount > 0 ORDER BY sequence_no DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_AR" ] && [ "$CURRENT_AR_ACTIVITY" -gt "$INITIAL_AR_ACTIVITY" ]; then
        echo "Found new payment in ar_activity table"
        PAYMENT_FOUND="true"
        PAYMENT_AMOUNT=$(echo "$NEWEST_AR" | cut -f2)
        PAYMENT_DATE=$(echo "$NEWEST_AR" | cut -f3)
        PAYMENT_NOTE=$(echo "$NEWEST_AR" | cut -f4)
        SESSION_ID=$(echo "$NEWEST_AR" | cut -f5)
        
        # Get method from ar_session if available
        if [ -n "$SESSION_ID" ]; then
            SESSION_INFO=$(openemr_query "SELECT payment_method, payment_type FROM ar_session WHERE session_id=$SESSION_ID" 2>/dev/null)
            PAYMENT_METHOD=$(echo "$SESSION_INFO" | cut -f1)
        fi
        
        echo "  Amount: $PAYMENT_AMOUNT"
        echo "  Method: $PAYMENT_METHOD"
        echo "  Note: $PAYMENT_NOTE"
        echo "  Date: $PAYMENT_DATE"
    fi
fi

# Query 3: Check ar_session for patient payments
if [ "$PAYMENT_FOUND" = "false" ]; then
    echo ""
    echo "=== Checking ar_session table ==="
    SESSION_DATA=$(openemr_query "SELECT session_id, patient_id, pay_total, payment_type, payment_method, description, created_time FROM ar_session WHERE patient_id=$PATIENT_PID ORDER BY session_id DESC LIMIT 5" 2>/dev/null)
    echo "Recent ar_session for patient:"
    echo "$SESSION_DATA"
    
    NEWEST_SESSION=$(openemr_query "SELECT session_id, pay_total, payment_type, payment_method, description, created_time FROM ar_session WHERE patient_id=$PATIENT_PID ORDER BY session_id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_SESSION" ] && [ "$CURRENT_AR_SESSION" -gt "$INITIAL_AR_SESSION" ]; then
        echo "Found new payment session"
        PAYMENT_FOUND="true"
        PAYMENT_ID=$(echo "$NEWEST_SESSION" | cut -f1)
        PAYMENT_AMOUNT=$(echo "$NEWEST_SESSION" | cut -f2)
        PAYMENT_TYPE=$(echo "$NEWEST_SESSION" | cut -f3)
        PAYMENT_METHOD=$(echo "$NEWEST_SESSION" | cut -f4)
        PAYMENT_NOTE=$(echo "$NEWEST_SESSION" | cut -f5)
        PAYMENT_DATE=$(echo "$NEWEST_SESSION" | cut -f6)
        
        echo "  Session ID: $PAYMENT_ID"
        echo "  Amount: $PAYMENT_AMOUNT"
        echo "  Type: $PAYMENT_TYPE"
        echo "  Method: $PAYMENT_METHOD"
        echo "  Note: $PAYMENT_NOTE"
        echo "  Date: $PAYMENT_DATE"
    fi
fi

# Also check if total payments increased (payment might be for different patient by mistake)
NEW_TOTAL_PAYMENTS=$((CURRENT_TOTAL - INITIAL_TOTAL))
echo ""
echo "New payments in system overall: $NEW_TOTAL_PAYMENTS"

# Check for any payment around $30 created recently
echo ""
echo "=== Searching for any $30 payment created during task ==="
THIRTY_PAYMENT=$(openemr_query "SELECT id, pid, amount1, amount2, method, source, dtime FROM payments WHERE (amount1 BETWEEN 29.99 AND 30.01 OR amount2 BETWEEN 29.99 AND 30.01) ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "Found \$30 payment: $THIRTY_PAYMENT"

# Normalize payment method for comparison
PAYMENT_METHOD_LOWER=$(echo "$PAYMENT_METHOD" | tr '[:upper:]' '[:lower:]')
IS_CASH="false"
if echo "$PAYMENT_METHOD_LOWER" | grep -qE "(cash|money|currency)"; then
    IS_CASH="true"
fi

# Check if note mentions copay
COMBINED_NOTES="$PAYMENT_NOTE $PAYMENT_SOURCE"
NOTES_LOWER=$(echo "$COMBINED_NOTES" | tr '[:upper:]' '[:lower:]')
MENTIONS_COPAY="false"
if echo "$NOTES_LOWER" | grep -qE "(copay|co-pay|copayment|office.?visit)"; then
    MENTIONS_COPAY="true"
fi

# Escape special characters for JSON
PAYMENT_NOTE_ESCAPED=$(echo "$PAYMENT_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ')
PAYMENT_SOURCE_ESCAPED=$(echo "$PAYMENT_SOURCE" | sed 's/"/\\"/g' | tr '\n' ' ')
PAYMENT_METHOD_ESCAPED=$(echo "$PAYMENT_METHOD" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/copay_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_counts": {
        "payments": ${INITIAL_PAYMENTS:-0},
        "ar_activity": ${INITIAL_AR_ACTIVITY:-0},
        "ar_session": ${INITIAL_AR_SESSION:-0},
        "total_payments": ${INITIAL_TOTAL:-0}
    },
    "current_counts": {
        "payments": ${CURRENT_PAYMENTS:-0},
        "ar_activity": ${CURRENT_AR_ACTIVITY:-0},
        "ar_session": ${CURRENT_AR_SESSION:-0},
        "total_payments": ${CURRENT_TOTAL:-0}
    },
    "payment_found": $PAYMENT_FOUND,
    "payment": {
        "id": "$PAYMENT_ID",
        "amount": "$PAYMENT_AMOUNT",
        "method": "$PAYMENT_METHOD_ESCAPED",
        "date": "$PAYMENT_DATE",
        "note": "$PAYMENT_NOTE_ESCAPED",
        "source": "$PAYMENT_SOURCE_ESCAPED"
    },
    "validation": {
        "is_cash": $IS_CASH,
        "mentions_copay": $MENTIONS_COPAY,
        "new_payments_for_patient": $((CURRENT_PAYMENTS - INITIAL_PAYMENTS)),
        "new_total_payments": $NEW_TOTAL_PAYMENTS
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/record_copay_result.json 2>/dev/null || sudo rm -f /tmp/record_copay_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_copay_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_copay_result.json
chmod 666 /tmp/record_copay_result.json 2>/dev/null || sudo chmod 666 /tmp/record_copay_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/record_copay_result.json"
cat /tmp/record_copay_result.json
echo ""
echo "=== Export Complete ==="