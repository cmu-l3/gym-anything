#!/bin/bash
echo "=== Exporting Import Bank Statement Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# 3. Query Database for New Statements
# We look for statements created AFTER task start time
# We specifically select the one with the most items if multiple exist
echo "Querying database for new bank statements..."

# SQL to get details of the most recently created statement after task start
# Returns: id | created_at | item_count | amounts_list | cash_account_id
DB_QUERY="
SELECT 
    bs.id, 
    bs.created_at,
    (SELECT COUNT(*) FROM bank_statement_items bsi WHERE bsi.bank_statement_id = bs.id) as item_count,
    (SELECT STRING_AGG(amount::text, ',') FROM bank_statement_items bsi WHERE bsi.bank_statement_id = bs.id) as amounts,
    bs.cash_id
FROM bank_statements bs 
WHERE extract(epoch from bs.created_at) > $TASK_START 
ORDER BY bs.created_at DESC 
LIMIT 1;
"

RESULT_ROW=$(ekylibre_db_query "$DB_QUERY")

STATEMENT_FOUND="false"
STATEMENT_ID=""
ITEM_COUNT="0"
AMOUNTS=""
CASH_ID=""

if [ -n "$RESULT_ROW" ]; then
    STATEMENT_FOUND="true"
    # Parse pipe-delimited output from psql -A -t
    STATEMENT_ID=$(echo "$RESULT_ROW" | cut -d'|' -f1)
    ITEM_COUNT=$(echo "$RESULT_ROW" | cut -d'|' -f3)
    AMOUNTS=$(echo "$RESULT_ROW" | cut -d'|' -f4)
    CASH_ID=$(echo "$RESULT_ROW" | cut -d'|' -f5)
fi

# 4. Get current total count to double check
CURRENT_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM bank_statements")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "statement_found": $STATEMENT_FOUND,
    "statement_details": {
        "id": "$STATEMENT_ID",
        "item_count": ${ITEM_COUNT:-0},
        "amounts": "$AMOUNTS",
        "cash_id": "$CASH_ID"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save result to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="