#!/bin/bash
# Export results for Semiconductor Wafer Yield Analysis
echo "=== Exporting Semiconductor Wafer Yield Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE querying database
take_screenshot /tmp/task_final_state.png ga

# Export Output Path
CSV_PATH="/home/ga/Documents/exports/lot_yield_report.csv"

# Initialize Verification Flags
STATS_VW_EXISTS=false
CLASS_VW_EXISTS=false
YIELD_VW_EXISTS=false

W1_EDGE_PCT=0
W2_R2_VAL=0
W1_SIGNATURE="NONE"
W2_SIGNATURE="NONE"
W4_SCRAP=0
L1_YIELD=0
L2_YIELD=0

CSV_EXISTS=false
CSV_SIZE=0

# ---------------------------------------------------------------
# Check WAFER_DEFECT_STATS_VW
# ---------------------------------------------------------------
VW1_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='FAB_ADMIN' AND view_name='WAFER_DEFECT_STATS_VW';" "system" | tr -d '[:space:]')
if [ "${VW1_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    STATS_VW_EXISTS=true
    
    # Wafer 1 should have high edge defect percent (~85.7)
    VAL1=$(oracle_query_raw "SELECT ROUND(NVL(edge_defect_pct, 0), 1) FROM fab_admin.wafer_defect_stats_vw WHERE wafer_id=1;" "system" | tr -d '[:space:]')
    if [[ "$VAL1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then W1_EDGE_PCT=$VAL1; fi
    
    # Wafer 2 should have high R_Squared (>=0.80)
    VAL2=$(oracle_query_raw "SELECT ROUND(NVL(r_squared, 0), 2) FROM fab_admin.wafer_defect_stats_vw WHERE wafer_id=2;" "system" | tr -d '[:space:]')
    if [[ "$VAL2" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then W2_R2_VAL=$VAL2; fi
fi

# ---------------------------------------------------------------
# Check WAFER_CLASSIFICATION_VW
# ---------------------------------------------------------------
VW2_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='FAB_ADMIN' AND view_name='WAFER_CLASSIFICATION_VW';" "system" | tr -d '[:space:]')
if [ "${VW2_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CLASS_VW_EXISTS=true
    
    W1_SIGNATURE=$(oracle_query_raw "SELECT UPPER(signature_type) FROM fab_admin.wafer_classification_vw WHERE wafer_id=1;" "system" | tr -d '[:space:]')
    W2_SIGNATURE=$(oracle_query_raw "SELECT UPPER(signature_type) FROM fab_admin.wafer_classification_vw WHERE wafer_id=2;" "system" | tr -d '[:space:]')
    
    VAL3=$(oracle_query_raw "SELECT NVL(is_scrap, 0) FROM fab_admin.wafer_classification_vw WHERE wafer_id=4;" "system" | tr -d '[:space:]')
    if [[ "$VAL3" =~ ^[0-9]+$ ]]; then W4_SCRAP=$VAL3; fi
fi

# ---------------------------------------------------------------
# Check LOT_YIELD_SUMMARY_VW
# ---------------------------------------------------------------
VW3_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='FAB_ADMIN' AND view_name='LOT_YIELD_SUMMARY_VW';" "system" | tr -d '[:space:]')
if [ "${VW3_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    YIELD_VW_EXISTS=true
    
    # Lot 1 (3 wafers, W1 and W2 are scrap, W3 is OK = 33% yield)
    VAL4=$(oracle_query_raw "SELECT ROUND(NVL(yield_pct, 0), 0) FROM fab_admin.lot_yield_summary_vw WHERE lot_id=1;" "system" | tr -d '[:space:]')
    if [[ "$VAL4" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then L1_YIELD=$VAL4; fi

    # Lot 2 (2 wafers, W4 is scrap (>100 defects), W5 is OK = 50% yield)
    VAL5=$(oracle_query_raw "SELECT ROUND(NVL(yield_pct, 0), 0) FROM fab_admin.lot_yield_summary_vw WHERE lot_id=2;" "system" | tr -d '[:space:]')
    if [[ "$VAL5" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then L2_YIELD=$VAL5; fi
fi

# ---------------------------------------------------------------
# Check CSV Export
# ---------------------------------------------------------------
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# ---------------------------------------------------------------
# Collect SQL Developer GUI Evidence
# ---------------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence)

# ---------------------------------------------------------------
# Write to JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/wafer_yield.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "stats_view_exists": $STATS_VW_EXISTS,
    "class_view_exists": $CLASS_VW_EXISTS,
    "yield_view_exists": $YIELD_VW_EXISTS,
    "w1_edge_pct": $W1_EDGE_PCT,
    "w2_r2_val": $W2_R2_VAL,
    "w1_signature": "$W1_SIGNATURE",
    "w2_signature": "$W2_SIGNATURE",
    "w4_scrap": $W4_SCRAP,
    "l1_yield": $L1_YIELD,
    "l2_yield": $L2_YIELD,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/wafer_yield_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/wafer_yield_result.json 2>/dev/null
chmod 666 /tmp/wafer_yield_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/wafer_yield_result.json"
cat /tmp/wafer_yield_result.json
echo "=== Export Complete ==="