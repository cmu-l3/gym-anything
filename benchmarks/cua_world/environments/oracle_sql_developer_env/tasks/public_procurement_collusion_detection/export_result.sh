#!/bin/bash
echo "=== Exporting Public Procurement Collusion Detection results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize flags
FUNC_NORMALIZED_OK=false
FUNC_TEST_RESULT=""
SC_VW_EXISTS=false
SC_VW_ROWS=0
MC_VW_EXISTS=false
MC_VW_ROWS=0
MC_C1_HHI=0
CB_VW_EXISTS=false
CB_VW_ROWS=0
CB_WINNER=""
CB_LOSER=""
VRS_TBL_EXISTS=false
VRS_ROWS=0
VRS_HIGH_RISK=0
CSV_EXISTS=false
CSV_SIZE=0

# 1. Address Normalization Function
FUNC_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'AUDIT_MGR' AND object_name = 'FUNC_NORMALIZE_ADDRESS' AND object_type = 'FUNCTION';" "system" | tr -d '[:space:]')
if [ "${FUNC_EXISTS:-0}" -gt 0 ]; then
    # Test string should resolve to: 123 FAKE ST STE A
    FUNC_TEST_RESULT=$(oracle_query_raw "SELECT AUDIT_MGR.FUNC_NORMALIZE_ADDRESS('123 Fake-Street, Suite A.') FROM DUAL;" "system" 2>/dev/null)
    if echo "$FUNC_TEST_RESULT" | grep -qi "123 FAKE ST STE A"; then
        FUNC_NORMALIZED_OK=true
    fi
fi

# 2. Shared Contacts View
SC_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'AUDIT_MGR' AND view_name = 'SHARED_CONTACTS_VW';" "system" | tr -d '[:space:]')
if [ "${SC_EXISTS:-0}" -gt 0 ]; then
    SC_VW_EXISTS=true
    SC_VW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM audit_mgr.SHARED_CONTACTS_VW;" "system" | tr -d '[:space:]')
    SC_VW_ROWS=${SC_VW_ROWS:-0}
fi

# 3. Market Concentration View
MC_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'AUDIT_MGR' AND view_name = 'MARKET_CONCENTRATION_VW';" "system" | tr -d '[:space:]')
if [ "${MC_EXISTS:-0}" -gt 0 ]; then
    MC_VW_EXISTS=true
    MC_VW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM audit_mgr.MARKET_CONCENTRATION_VW;" "system" | tr -d '[:space:]')
    MC_VW_ROWS=${MC_VW_ROWS:-0}
    MC_C1_HHI=$(oracle_query_raw "SELECT hhi_score FROM audit_mgr.MARKET_CONCENTRATION_VW WHERE category_id = 1;" "system" | tr -d '[:space:]')
    MC_C1_HHI=${MC_C1_HHI:-0}
fi

# 4. Complementary Bids View
CB_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'AUDIT_MGR' AND view_name = 'COMPLEMENTARY_BIDS_VW';" "system" | tr -d '[:space:]')
if [ "${CB_EXISTS:-0}" -gt 0 ]; then
    CB_VW_EXISTS=true
    CB_VW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM audit_mgr.COMPLEMENTARY_BIDS_VW;" "system" | tr -d '[:space:]')
    CB_VW_ROWS=${CB_VW_ROWS:-0}
    if [ "$CB_VW_ROWS" -gt 0 ]; then
        CB_WINNER=$(oracle_query_raw "SELECT winning_vendor_id FROM audit_mgr.COMPLEMENTARY_BIDS_VW WHERE ROWNUM = 1;" "system" | tr -d '[:space:]')
        CB_LOSER=$(oracle_query_raw "SELECT losing_vendor_id FROM audit_mgr.COMPLEMENTARY_BIDS_VW WHERE ROWNUM = 1;" "system" | tr -d '[:space:]')
    fi
fi

# 5. Vendor Risk Scores Table
VRS_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'AUDIT_MGR' AND table_name = 'VENDOR_RISK_SCORES';" "system" | tr -d '[:space:]')
if [ "${VRS_EXISTS:-0}" -gt 0 ]; then
    VRS_TBL_EXISTS=true
    VRS_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM audit_mgr.VENDOR_RISK_SCORES;" "system" | tr -d '[:space:]')
    VRS_ROWS=${VRS_ROWS:-0}
    VRS_HIGH_RISK=$(oracle_query_raw "SELECT COUNT(*) FROM audit_mgr.VENDOR_RISK_SCORES WHERE risk_score > 0;" "system" | tr -d '[:space:]')
    VRS_HIGH_RISK=${VRS_HIGH_RISK:-0}
fi

# 6. CSV Export
CSV_PATH="/home/ga/Documents/exports/high_risk_vendors.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null)
fi

# Write results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "func_normalized_ok": $FUNC_NORMALIZED_OK,
    "func_test_result": "$(echo "$FUNC_TEST_RESULT" | tr -d '"\n\r')",
    "sc_vw_exists": $SC_VW_EXISTS,
    "sc_vw_rows": $SC_VW_ROWS,
    "mc_vw_exists": $MC_VW_EXISTS,
    "mc_vw_rows": $MC_VW_ROWS,
    "mc_c1_hhi": $MC_C1_HHI,
    "cb_vw_exists": $CB_VW_EXISTS,
    "cb_vw_rows": $CB_VW_ROWS,
    "cb_winner": "$CB_WINNER",
    "cb_loser": "$CB_LOSER",
    "vrs_tbl_exists": $VRS_TBL_EXISTS,
    "vrs_rows": $VRS_ROWS,
    "vrs_high_risk": $VRS_HIGH_RISK,
    "csv_exists": $CSV_EXISTS,
    "csv_size": ${CSV_SIZE:-0},
    $(collect_gui_evidence)
}
EOF

# Move to final location safely
rm -f /tmp/procurement_result.json 2>/dev/null || sudo rm -f /tmp/procurement_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/procurement_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/procurement_result.json
chmod 666 /tmp/procurement_result.json 2>/dev/null || sudo chmod 666 /tmp/procurement_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/procurement_result.json"
cat /tmp/procurement_result.json