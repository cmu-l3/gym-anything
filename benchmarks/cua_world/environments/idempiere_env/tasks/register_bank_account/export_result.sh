#!/bin/bash
echo "=== Exporting register_bank_account results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/register_bank_account_final.png

# ------------------------------------------------------------------
# Query Database for the Result
# ------------------------------------------------------------------
echo "--- Querying iDempiere Database ---"

CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# We need to join C_Bank and C_BankAccount to verify the relationship
# Using JSON aggregation to get a structured result directly from Postgres if possible,
# but since psql version might vary, we'll fetch raw fields and construct JSON in bash.

# Query for the specific bank we expect
BANK_QUERY="
SELECT 
    b.c_bank_id, 
    b.name, 
    b.routingno, 
    b.isactive,
    ba.c_bankaccount_id,
    ba.accountno,
    ba.name as account_name,
    ba.bankaccounttype,
    c.iso_code as currency
FROM c_bank b
LEFT JOIN c_bankaccount ba ON b.c_bank_id = ba.c_bank_id
LEFT JOIN c_currency c ON ba.c_currency_id = c.c_currency_id
WHERE b.name = 'Metro City Bank' 
  AND b.ad_client_id = $CLIENT_ID
ORDER BY b.created DESC, ba.created DESC
LIMIT 1;
"

# Execute query using the helper function but capturing output
# We use psql directly here to control the delimiter for easier parsing
RESULT_LINE=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|" -c "$BANK_QUERY" 2>/dev/null || echo "")

# Parse the result (delimiter is |)
# Format: id|name|routing|active|acct_id|acct_no|acct_name|type|currency
BANK_ID=$(echo "$RESULT_LINE" | cut -d'|' -f1)
BANK_NAME=$(echo "$RESULT_LINE" | cut -d'|' -f2)
ROUTING_NO=$(echo "$RESULT_LINE" | cut -d'|' -f3)
IS_ACTIVE=$(echo "$RESULT_LINE" | cut -d'|' -f4)
ACCT_ID=$(echo "$RESULT_LINE" | cut -d'|' -f5)
ACCT_NO=$(echo "$RESULT_LINE" | cut -d'|' -f6)
ACCT_NAME=$(echo "$RESULT_LINE" | cut -d'|' -f7)
ACCT_TYPE=$(echo "$RESULT_LINE" | cut -d'|' -f8)
CURRENCY=$(echo "$RESULT_LINE" | cut -d'|' -f9)

# Check creation timestamps to ensure they were created during the task
# We check the 'created' column in the database against task start time
# Converting SQL timestamp to epoch is tricky in pure bash/sql cross-env, 
# so we'll check if the record count increased instead as a proxy for "newness",
# OR we can just rely on the fact that we cleaned up the specific name in setup.
# Since we renamed old records in setup, finding a record with the exact name 
# means it was created or modified during this session.

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bank_found": $([ -n "$BANK_ID" ] && echo "true" || echo "false"),
    "bank": {
        "id": "${BANK_ID:-}",
        "name": "${BANK_NAME:-}",
        "routing_no": "${ROUTING_NO:-}",
        "is_active": "${IS_ACTIVE:-}"
    },
    "account_found": $([ -n "$ACCT_ID" ] && echo "true" || echo "false"),
    "account": {
        "id": "${ACCT_ID:-}",
        "account_no": "${ACCT_NO:-}",
        "name": "${ACCT_NAME:-}",
        "type": "${ACCT_TYPE:-}",
        "currency": "${CURRENCY:-}"
    },
    "screenshot_path": "/tmp/register_bank_account_final.png"
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