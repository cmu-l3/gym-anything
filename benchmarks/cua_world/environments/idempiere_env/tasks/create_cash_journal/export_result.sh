#!/bin/bash
set -e
echo "=== Exporting Cash Journal Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_cash_count.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Data Extraction
# ---------------------------------------------------------------
CLIENT_ID=$(get_gardenworld_client_id)

# Query for the most recently created Cash Journal
# We check if ID > last known, or created after start time
# To be robust, we select the latest record created for this client.
LATEST_CASH_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT 
        c.c_cash_id,
        c.name,
        c.description,
        TO_CHAR(c.statementdate, 'YYYY-MM-DD') as statementdate,
        c.docstatus,
        c.created,
        EXTRACT(EPOCH FROM c.created) as created_epoch,
        (SELECT count(*) FROM c_cashline cl WHERE cl.c_cash_id = c.c_cash_id) as line_count
    FROM c_cash c
    WHERE c.ad_client_id = $CLIENT_ID
    ORDER BY c.c_cash_id DESC
    LIMIT 1
) t
" 2>/dev/null || echo "")

# If no JSON returned, database might be empty or query failed
if [ -z "$LATEST_CASH_JSON" ]; then
    LATEST_CASH_JSON="null"
    CASH_ID="0"
else
    # Extract ID for line query
    CASH_ID=$(echo "$LATEST_CASH_JSON" | jq -r '.c_cash_id')
fi

# Query lines for this cash journal
LINES_JSON="[]"
if [ "$CASH_ID" != "0" ] && [ "$CASH_ID" != "" ]; then
    LINES_JSON=$(idempiere_query "
    SELECT json_agg(row_to_json(t)) FROM (
        SELECT 
            cl.line,
            cl.cashtype,
            ch.name as charge_name,
            cl.amount,
            cl.description
        FROM c_cashline cl
        LEFT JOIN c_charge ch ON cl.c_charge_id = ch.c_charge_id
        WHERE cl.c_cash_id = $CASH_ID
        ORDER BY cl.line
    ) t
    " 2>/dev/null || echo "[]")
fi

# ---------------------------------------------------------------
# Prepare Result JSON
# ---------------------------------------------------------------
# Create temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "latest_cash_record": $LATEST_CASH_JSON,
    "cash_lines": $LINES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="