#!/bin/bash
echo "=== Exporting prepare_payment_batch results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get task start time
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert unix timestamp to postgres timestamp format (approximate is fine for verification)
# We usually rely on the fact that the agent creates records *after* the script runs.
# In SQL, we can compare created > to_timestamp(TASK_START_TS)

CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

echo "Exporting verification data for Client ID: $CLIENT_ID, Start Time: $TASK_START_TS"

# -----------------------------------------------------------------------------
# 1. FIND THE INVOICE
# Look for a Vendor Invoice (issotrx='N') for Joe Block with GrandTotal=150
# created after task start.
# -----------------------------------------------------------------------------
echo "Searching for target invoice..."

# Get Joe Block's ID
BP_ID=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE name='Joe Block' AND ad_client_id=$CLIENT_ID LIMIT 1")

INVOICE_QUERY="
SELECT 
    c_invoice_id, 
    documentno, 
    docstatus, 
    grandtotal 
FROM c_invoice 
WHERE 
    issotrx='N' 
    AND c_bpartner_id='$BP_ID' 
    AND grandtotal=150.00 
    AND created >= to_timestamp($TASK_START_TS)
    AND ad_client_id=$CLIENT_ID
ORDER BY created DESC 
LIMIT 1
"

INVOICE_DATA=$(idempiere_query "$INVOICE_QUERY")

INVOICE_ID=""
INVOICE_STATUS=""
INVOICE_FOUND="false"

if [ -n "$INVOICE_DATA" ]; then
    INVOICE_FOUND="true"
    INVOICE_ID=$(echo "$INVOICE_DATA" | cut -d'|' -f1)
    # Status/Total might be merged in output, query them specifically if needed or parse carefully
    # psql -A -t uses pipe separator by default if multiple columns, but here we just need ID mostly
    # Let's re-query specific fields to be safe
    INVOICE_ID=$(echo "$INVOICE_DATA" | awk -F'|' '{print $1}')
    INVOICE_STATUS=$(echo "$INVOICE_DATA" | awk -F'|' '{print $3}')
    echo "  Found Invoice: ID=$INVOICE_ID, Status=$INVOICE_STATUS"
else
    echo "  No matching invoice found."
fi

# -----------------------------------------------------------------------------
# 2. FIND THE PAYMENT SELECTION
# Look for a Payment Selection created after task start.
# -----------------------------------------------------------------------------
echo "Searching for payment selection batch..."

PAYSEL_QUERY="
SELECT 
    ps.c_payselection_id, 
    ps.name, 
    ba.name as bank_name
FROM c_payselection ps
JOIN c_bankaccount ba ON ps.c_bankaccount_id = ba.c_bankaccount_id
WHERE 
    ps.ad_client_id=$CLIENT_ID
    AND ps.created >= to_timestamp($TASK_START_TS)
ORDER BY ps.created DESC 
LIMIT 1
"

PAYSEL_DATA=$(idempiere_query "$PAYSEL_QUERY")

PAYSEL_ID=""
PAYSEL_NAME=""
BANK_NAME=""
PAYSEL_FOUND="false"

if [ -n "$PAYSEL_DATA" ]; then
    PAYSEL_FOUND="true"
    PAYSEL_ID=$(echo "$PAYSEL_DATA" | awk -F'|' '{print $1}')
    PAYSEL_NAME=$(echo "$PAYSEL_DATA" | awk -F'|' '{print $2}')
    BANK_NAME=$(echo "$PAYSEL_DATA" | awk -F'|' '{print $3}')
    echo "  Found Payment Selection: ID=$PAYSEL_ID, Name=$PAYSEL_NAME, Bank=$BANK_NAME"
else
    echo "  No payment selection found."
fi

# -----------------------------------------------------------------------------
# 3. VERIFY LINKAGE (The Crucial Step)
# Check if the Payment Selection Line exists linking the two
# -----------------------------------------------------------------------------
LINKAGE_FOUND="false"

if [ "$INVOICE_FOUND" = "true" ] && [ "$PAYSEL_FOUND" = "true" ]; then
    echo "Checking linkage between Invoice $INVOICE_ID and Payment Selection $PAYSEL_ID..."
    
    LINK_QUERY="SELECT COUNT(*) FROM c_payselectionline WHERE c_payselection_id=$PAYSEL_ID AND c_invoice_id=$INVOICE_ID"
    LINK_COUNT=$(idempiere_query "$LINK_QUERY")
    
    if [ "$LINK_COUNT" -gt 0 ]; then
        LINKAGE_FOUND="true"
        echo "  Linkage confirmed! ($LINK_COUNT lines)"
    else
        echo "  No linkage found."
    fi
fi

# -----------------------------------------------------------------------------
# 4. CAPTURE FINAL SCREENSHOT
# -----------------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------------
# 5. GENERATE RESULT JSON
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "invoice_found": $INVOICE_FOUND,
    "invoice_id": "${INVOICE_ID:-0}",
    "invoice_status": "${INVOICE_STATUS:-}",
    "payment_selection_found": $PAYSEL_FOUND,
    "payment_selection_id": "${PAYSEL_ID:-0}",
    "payment_selection_name": "${PAYSEL_NAME:-}",
    "bank_account_name": "${BANK_NAME:-}",
    "linkage_found": $LINKAGE_FOUND,
    "task_timestamp": $TASK_START_TS
}
EOF

# Move to standard output location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json