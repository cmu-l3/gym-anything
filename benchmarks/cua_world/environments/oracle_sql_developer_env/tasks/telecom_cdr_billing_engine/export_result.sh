#!/bin/bash
echo "=== Exporting Telecom CDR Billing Engine Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize flags and data
RATED_CDRS_EXISTS="false"
RATED_COUNT="0"
INVOICE_MV_EXISTS="false"
CSV_EXISTS="false"
CSV_SIZE="0"

CDR1_DEST=""
CDR1_COST=""
CDR1_MINS=""
CDR2_COST=""
CDR3_COST=""
CDR4_DEST=""
CDR4_COST=""

# 1. Check RATED_CDRS table
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'BILLING' AND table_name = 'RATED_CDRS';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    RATED_CDRS_EXISTS="true"
    RATED_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM billing.rated_cdrs;" "system" | tr -d '[:space:]')
    
    # Extract specific values for verification
    if [ "${RATED_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        # Use TRIM to remove any potential trailing spaces
        CDR1_DEST=$(oracle_query_raw "SELECT TRIM(destination_name) FROM billing.rated_cdrs WHERE cdr_id = 1;" "system")
        CDR1_COST=$(oracle_query_raw "SELECT total_cost FROM billing.rated_cdrs WHERE cdr_id = 1;" "system" | tr -d '[:space:]')
        CDR1_MINS=$(oracle_query_raw "SELECT billable_minutes FROM billing.rated_cdrs WHERE cdr_id = 1;" "system" | tr -d '[:space:]')
        
        CDR2_COST=$(oracle_query_raw "SELECT total_cost FROM billing.rated_cdrs WHERE cdr_id = 2;" "system" | tr -d '[:space:]')
        CDR3_COST=$(oracle_query_raw "SELECT total_cost FROM billing.rated_cdrs WHERE cdr_id = 3;" "system" | tr -d '[:space:]')
        
        CDR4_DEST=$(oracle_query_raw "SELECT TRIM(destination_name) FROM billing.rated_cdrs WHERE cdr_id = 4;" "system")
        CDR4_COST=$(oracle_query_raw "SELECT total_cost FROM billing.rated_cdrs WHERE cdr_id = 4;" "system" | tr -d '[:space:]')
    fi
fi

# 2. Check CUSTOMER_INVOICE_MV
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'BILLING' AND mview_name = 'CUSTOMER_INVOICE_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    INVOICE_MV_EXISTS="true"
fi

# 3. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/customer_invoices.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 4. Check GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export to JSON safely
TEMP_JSON=$(mktemp /tmp/telecom_billing_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "rated_cdrs_exists": $RATED_CDRS_EXISTS,
    "rated_count": "${RATED_COUNT:-0}",
    "cdr1_dest": "${CDR1_DEST:-none}",
    "cdr1_cost": "${CDR1_COST:-0}",
    "cdr1_mins": "${CDR1_MINS:-0}",
    "cdr2_cost": "${CDR2_COST:-0}",
    "cdr3_cost": "${CDR3_COST:-0}",
    "cdr4_dest": "${CDR4_DEST:-none}",
    "cdr4_cost": "${CDR4_COST:-0}",
    "invoice_mv_exists": $INVOICE_MV_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": "${CSV_SIZE:-0}",
    ${GUI_EVIDENCE}
}
EOF

# Move securely
rm -f /tmp/telecom_billing_result.json 2>/dev/null || sudo rm -f /tmp/telecom_billing_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/telecom_billing_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/telecom_billing_result.json
chmod 666 /tmp/telecom_billing_result.json 2>/dev/null || sudo chmod 666 /tmp/telecom_billing_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/telecom_billing_result.json"
cat /tmp/telecom_billing_result.json
echo "=== Export complete ==="