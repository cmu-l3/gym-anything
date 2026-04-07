#!/bin/bash
echo "=== Exporting configure_recurring_invoice results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Get task start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 2. Capture final screenshot
take_screenshot /tmp/task_final.png

# 3. Query: Find the Template Invoice
# Looking for an invoice for C&W (value='C&W') created after start time with GrandTotal 150.00
echo "--- Searching for Template Invoice ---"
# We select the most recent one matching criteria
INVOICE_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT i.c_invoice_id, i.documentno, i.grandtotal, i.created
    FROM c_invoice i
    JOIN c_bpartner bp ON i.c_bpartner_id = bp.c_bpartner_id
    WHERE bp.value = 'C&W'
      AND i.grandtotal = 150.00
      AND i.ad_client_id = $CLIENT_ID
      AND i.created > to_timestamp($START_TIME)
    ORDER BY i.created DESC
    LIMIT 1
) t
" 2>/dev/null)

if [ -z "$INVOICE_JSON" ]; then
    INVOICE_JSON="null"
    echo "No matching template invoice found."
else
    echo "Found Invoice: $INVOICE_JSON"
fi

# 4. Query: Find the Recurring Record
# Looking for Recurring record with specific name created after start time
echo "--- Searching for Recurring Record ---"
RECURRING_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT r.c_recurring_id, r.name, r.recurringtype, r.frequencytype, r.runsmax, r.c_invoice_id, r.created
    FROM c_recurring r
    WHERE r.name = 'C&W Monthly Maintenance 2025'
      AND r.ad_client_id = $CLIENT_ID
      AND r.created > to_timestamp($START_TIME)
    LIMIT 1
) t
" 2>/dev/null)

if [ -z "$RECURRING_JSON" ]; then
    RECURRING_JSON="null"
    echo "No matching recurring record found."
else
    echo "Found Recurring Record: $RECURRING_JSON"
fi

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "template_invoice": $INVOICE_JSON,
    "recurring_record": $RECURRING_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# 6. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="