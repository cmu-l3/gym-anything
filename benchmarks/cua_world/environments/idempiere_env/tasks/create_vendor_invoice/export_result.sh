#!/bin/bash
set -e
echo "=== Exporting create_vendor_invoice result ==="
source /workspace/scripts/task_utils.sh

# 1. Gather Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CLIENT_ID=$(get_gardenworld_client_id)

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Query Database for Result
# We look for the most recently created AP Invoice for Seed Farm Inc.
echo "Querying database for created invoice..."

# This SQL constructs a JSON object directly from the database for the most recent matching invoice
# We filter by created > task_start timestamp
SQL_QUERY="
WITH recent_invoice AS (
    SELECT 
        i.c_invoice_id,
        i.documentno,
        i.docstatus,
        i.grandtotal,
        i.created,
        bp.name as bpartner_name,
        i.description
    FROM c_invoice i
    JOIN c_bpartner bp ON i.c_bpartner_id = bp.c_bpartner_id
    WHERE i.issotrx='N' 
      AND i.ad_client_id=$CLIENT_ID
      AND bp.name = 'Seed Farm Inc.'
      AND i.created >= to_timestamp($TASK_START)
    ORDER BY i.created DESC
    LIMIT 1
),
invoice_lines AS (
    SELECT 
        il.c_invoice_id,
        p.name as product_name,
        il.qtyinvoiced,
        il.priceactual,
        il.linenetamt
    FROM c_invoiceline il
    JOIN m_product p ON il.m_product_id = p.m_product_id
    WHERE il.c_invoice_id IN (SELECT c_invoice_id FROM recent_invoice)
)
SELECT row_to_json(t)
FROM (
    SELECT 
        ri.*,
        (SELECT json_agg(il) FROM invoice_lines il) as lines
    FROM recent_invoice ri
) t;
"

# Execute query inside docker
JSON_RESULT=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -c "$SQL_QUERY" 2>/dev/null || echo "")

# 4. Check global counts (Backup check)
INITIAL_COUNT=$(cat /tmp/initial_ap_invoice_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# 5. Construct Final JSON
# We wrap the database result in a larger object containing task metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "found_invoice": ${JSON_RESULT:-null},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="