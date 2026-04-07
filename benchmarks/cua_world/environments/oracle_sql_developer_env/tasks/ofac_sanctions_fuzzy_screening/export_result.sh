#!/bin/bash
# Export script for OFAC Sanctions Fuzzy Screening task
echo "=== Exporting OFAC Sanctions Fuzzy Screening results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Initialize assessment variables
VIEW_EXISTS="false"
USES_UTL_MATCH="false"
USES_ALT_ALIASES="false"
TP_HOLDS=0
FP_HOLDS=0
CSV_EXISTS="false"
CSV_SIZE=0

# 1. Check if HIGH_RISK_MATCHES_VW exists
VIEW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'COMPLIANCE_OFFICER' AND view_name = 'HIGH_RISK_MATCHES_VW';" "system" | tr -d '[:space:]')
if [ "${VIEW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIEW_EXISTS="true"
    
    # 2. Extract DDL to check for UTL_MATCH and OFAC_ALT
    # Using DBMS_METADATA to avoid LONG column truncation issues
    VW_DDL=$(oracle_query_raw "SELECT DBMS_METADATA.GET_DDL('VIEW', 'HIGH_RISK_MATCHES_VW', 'COMPLIANCE_OFFICER') FROM DUAL;" "system" 2>/dev/null)
    
    if echo "$VW_DDL" | grep -qi "JARO_WINKLER"; then
        USES_UTL_MATCH="true"
    fi
    
    if echo "$VW_DDL" | grep -qi "OFAC_ALT"; then
        USES_ALT_ALIASES="true"
    fi
fi

# 3. Assess ERP_ORDERS updates (Compliance Holds)
# True Positives: Order IDs 1001 through 1006
TP_HOLDS=$(oracle_query_raw "SELECT COUNT(*) FROM compliance_officer.erp_orders WHERE status = 'COMPLIANCE_HOLD' AND order_id IN (1001, 1002, 1003, 1004, 1005, 1006);" "system" | tr -d '[:space:]')
TP_HOLDS=${TP_HOLDS:-0}

# False Positives: Any other order IDs
FP_HOLDS=$(oracle_query_raw "SELECT COUNT(*) FROM compliance_officer.erp_orders WHERE status = 'COMPLIANCE_HOLD' AND order_id NOT IN (1001, 1002, 1003, 1004, 1005, 1006);" "system" | tr -d '[:space:]')
FP_HOLDS=${FP_HOLDS:-0}

# 4. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/compliance_holds.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 5. Collect GUI Evidence (from task_utils.sh)
GUI_EVIDENCE=$(collect_gui_evidence)

# 6. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "view_exists": $VIEW_EXISTS,
    "uses_utl_match": $USES_UTL_MATCH,
    "uses_alt_aliases": $USES_ALT_ALIASES,
    "tp_holds": $TP_HOLDS,
    "fp_holds": $FP_HOLDS,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Move to final location safely
rm -f /tmp/ofac_task_result.json 2>/dev/null || sudo rm -f /tmp/ofac_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ofac_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ofac_task_result.json
chmod 666 /tmp/ofac_task_result.json 2>/dev/null || sudo chmod 666 /tmp/ofac_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/ofac_task_result.json"
cat /tmp/ofac_task_result.json
echo "=== Export complete ==="