#!/bin/bash
echo "=== Exporting record_outgoing_payment result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# =============================================================================
# DATABASE VERIFICATION
# =============================================================================

# We look for a payment created AFTER the task start time with the correct amount.
# We join with entities to get the payee name.

echo "Querying database for new outgoing payment..."

# SQL query to fetch details of the most recent payment matching criteria
# We check:
# 1. Amount = 3250.00
# 2. Created after task start
# 3. Payee name
# 4. Date (to_bank_at)

# Note: In Postgres, created_at is timestamp. We compare against task start timestamp.
# We output JSON directly from the query for easiest parsing.

SQL_QUERY="
WITH task_payments AS (
    SELECT 
        op.id,
        op.amount,
        op.to_bank_at,
        op.created_at,
        e.name as payee_name
    FROM outgoing_payments op
    LEFT JOIN entities e ON op.payee_id = e.id
    WHERE op.created_at >= to_timestamp($TASK_START)
    ORDER BY op.created_at DESC
    LIMIT 1
)
SELECT row_to_json(t) FROM task_payments t;
"

# Execute query
PAYMENT_JSON=$(ekylibre_db_query "$SQL_QUERY")

# If no payment found matching strict time criteria, let's just get the very last payment created
# to provide debugging feedback (e.g., "You created a payment but the amount was wrong")
if [ -z "$PAYMENT_JSON" ]; then
    DEBUG_QUERY="
    SELECT row_to_json(t) FROM (
        SELECT op.amount, op.to_bank_at, op.created_at, e.name as payee_name 
        FROM outgoing_payments op 
        LEFT JOIN entities e ON op.payee_id = e.id 
        ORDER BY op.created_at DESC LIMIT 1
    ) t;
    "
    LAST_PAYMENT_DEBUG=$(ekylibre_db_query "$DEBUG_QUERY")
else
    LAST_PAYMENT_DEBUG="null"
fi

# Get initial count to verify increment
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM outgoing_payments")
COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# =============================================================================
# EXPORT JSON
# =============================================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "count_diff": $COUNT_DIFF,
    "found_payment": ${PAYMENT_JSON:-null},
    "last_payment_debug": ${LAST_PAYMENT_DEBUG:-null},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="