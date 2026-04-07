#!/bin/bash
echo "=== Exporting SEC EDGAR XML Shredding Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize metrics
TBL_EXISTS=false
EXTRACTED_COUNT=0
NULL_ISSUER_COUNT=99

VW_EXISTS=false
ANOMALY_YES_COUNT=0
CORRECTED_MATH_COUNT=0

CSV_EXISTS=false
CSV_SIZE=0

# Check Table Requirements
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'EDGAR_ADMIN' AND table_name = 'EXTRACTED_HOLDINGS';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TBL_EXISTS=true
    EXTRACTED_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM edgar_admin.extracted_holdings;" "system" | tr -d '[:space:]')
    NULL_ISSUER_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM edgar_admin.extracted_holdings WHERE issuer_name IS NULL;" "system" | tr -d '[:space:]')
fi

# Check View Requirements
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'EDGAR_ADMIN' AND view_name = 'VW_HOLDINGS_CORRECTED';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VW_EXISTS=true
    ANOMALY_YES_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM edgar_admin.vw_holdings_corrected WHERE anomaly_flag = 'YES';" "system" | tr -d '[:space:]')
    CORRECTED_MATH_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM edgar_admin.vw_holdings_corrected WHERE anomaly_flag = 'YES' AND corrected_value = reported_value / 1000;" "system" | tr -d '[:space:]')
fi

# Check CSV Requirements
CSV_PATH="/home/ga/Documents/exports/aapl_top_holders.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Compile JSON Output
cat > /tmp/sec_edgar_result.json << EOF
{
  "extracted_table_exists": $TBL_EXISTS,
  "extracted_count": ${EXTRACTED_COUNT:-0},
  "null_issuer_count": ${NULL_ISSUER_COUNT:-99},
  "corrected_view_exists": $VW_EXISTS,
  "anomaly_yes_count": ${ANOMALY_YES_COUNT:-0},
  "corrected_math_count": ${CORRECTED_MATH_COUNT:-0},
  "csv_exists": $CSV_EXISTS,
  "csv_size": $CSV_SIZE,
  $(collect_gui_evidence)
}
EOF

chmod 666 /tmp/sec_edgar_result.json
cat /tmp/sec_edgar_result.json
echo "=== Export Complete ==="