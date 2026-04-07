#!/bin/bash
# Export results for SaaS Billing Reconciliation task
echo "=== Exporting Billing Reconciliation results ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png ga

# Sanitize helpers
sanitize_float() { local val="$1" default="$2"; if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then echo "$val"; else echo "$default"; fi; }

# ---------------------------------------------------------------
# 1. Check CALC_EXPECTED_BILLING function
# ---------------------------------------------------------------
FUNC_EXISTS="false"
FUNC_TEST_FLAT=""
FUNC_TEST_CANCEL=""
FUNC_TEST_TIERED=""
FUNC_SOURCE_HAS_GRADUATED=""

FUNC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'BILLING_OPS' AND object_name = 'CALC_EXPECTED_BILLING' AND object_type = 'FUNCTION';" "system" | tr -d '[:space:]')
if [ "${FUNC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FUNC_EXISTS="true"

    # Test 1: customer 1, Jan 2025 (Starter, FLAT $49)
    FUNC_TEST_FLAT=$(oracle_query_raw "SELECT billing_ops.CALC_EXPECTED_BILLING(1, DATE '2025-01-01') FROM DUAL;" "system" 2>/dev/null | tr -d '[:space:]')
    FUNC_TEST_FLAT=$(sanitize_float "$FUNC_TEST_FLAT" "")

    # Test 2: customer 14, Jan 2025 (cancelled, should be NULL or 0)
    FUNC_TEST_CANCEL=$(oracle_query_raw "SELECT NVL(billing_ops.CALC_EXPECTED_BILLING(14, DATE '2025-01-01'), -999) FROM DUAL;" "system" 2>/dev/null | tr -d '[:space:]')
    FUNC_TEST_CANCEL=$(sanitize_float "$FUNC_TEST_CANCEL" "")

    # Test 3: customer 3, Dec 2024 (Business, graduated 15K API calls, expected ~$79)
    FUNC_TEST_TIERED=$(oracle_query_raw "SELECT billing_ops.CALC_EXPECTED_BILLING(3, DATE '2024-12-01') FROM DUAL;" "system" 2>/dev/null | tr -d '[:space:]')
    FUNC_TEST_TIERED=$(sanitize_float "$FUNC_TEST_TIERED" "")

    # Check source for graduated pricing logic keywords
    FUNC_TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'BILLING_OPS' AND name = 'CALC_EXPECTED_BILLING' AND type = 'FUNCTION';" "system" 2>/dev/null)
    if echo "$FUNC_TEXT" | grep -qiE "pricing_tiers|min_quantity|max_quantity|graduated|band|remaining" 2>/dev/null; then
        FUNC_SOURCE_HAS_GRADUATED="true"
    else
        FUNC_SOURCE_HAS_GRADUATED="false"
    fi
fi

# ---------------------------------------------------------------
# 2. Check VW_BILLING_DISCREPANCIES view
# ---------------------------------------------------------------
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
DISTINCT_DISC_TYPES=0
DISC_TYPES_LIST=""

VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'BILLING_OPS' AND view_name = 'VW_BILLING_DISCREPANCIES';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIEW_EXISTS="true"

    VIEW_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM billing_ops.vw_billing_discrepancies;" "system" 2>/dev/null | tr -d '[:space:]')
    VIEW_ROW_COUNT=$(sanitize_float "$VIEW_ROW_COUNT" "0")

    DISTINCT_DISC_TYPES=$(oracle_query_raw "SELECT COUNT(DISTINCT discrepancy_type) FROM billing_ops.vw_billing_discrepancies;" "system" 2>/dev/null | tr -d '[:space:]')
    DISTINCT_DISC_TYPES=$(sanitize_float "$DISTINCT_DISC_TYPES" "0")

    DISC_TYPES_LIST=$(oracle_query_raw "SELECT LISTAGG(discrepancy_type, ',') WITHIN GROUP (ORDER BY discrepancy_type) FROM (SELECT DISTINCT discrepancy_type FROM billing_ops.vw_billing_discrepancies);" "system" 2>/dev/null | tr -d '\r\n')
fi

# ---------------------------------------------------------------
# 3. Check BILLING_ADJUSTMENTS table
# ---------------------------------------------------------------
ADJ_TABLE_EXISTS="false"
ADJ_ROW_COUNT=0
ADJ_HAS_REQUIRED_COLS="false"
ADJ_HAS_NONZERO_AMOUNTS="false"

ADJ_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'BILLING_OPS' AND table_name = 'BILLING_ADJUSTMENTS';" "system" | tr -d '[:space:]')
if [ "${ADJ_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ADJ_TABLE_EXISTS="true"

    ADJ_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM billing_ops.billing_adjustments;" "system" 2>/dev/null | tr -d '[:space:]')
    ADJ_ROW_COUNT=$(sanitize_float "$ADJ_ROW_COUNT" "0")

    # Check for required columns
    ADJ_COL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner = 'BILLING_OPS' AND table_name = 'BILLING_ADJUSTMENTS' AND column_name IN ('CUSTOMER_ID','DISCREPANCY_TYPE','ORIGINAL_AMOUNT','CORRECT_AMOUNT','ADJUSTMENT_AMOUNT');" "system" | tr -d '[:space:]')
    if [ "${ADJ_COL_COUNT:-0}" -ge 4 ] 2>/dev/null; then
        ADJ_HAS_REQUIRED_COLS="true"
    fi

    # Check for non-zero adjustment amounts
    NONZERO_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM billing_ops.billing_adjustments WHERE adjustment_amount != 0;" "system" 2>/dev/null | tr -d '[:space:]')
    if [ "${NONZERO_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        ADJ_HAS_NONZERO_AMOUNTS="true"
    fi
fi

# ---------------------------------------------------------------
# 4. Check MV_REVENUE_IMPACT materialized view
# ---------------------------------------------------------------
MV_EXISTS="false"
MV_ROW_COUNT=0
MV_HAS_SEGMENT="false"

MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'BILLING_OPS' AND mview_name = 'MV_REVENUE_IMPACT';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MV_EXISTS="true"

    MV_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM billing_ops.mv_revenue_impact;" "system" 2>/dev/null | tr -d '[:space:]')
    MV_ROW_COUNT=$(sanitize_float "$MV_ROW_COUNT" "0")

    MV_SEG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner = 'BILLING_OPS' AND table_name = 'MV_REVENUE_IMPACT' AND column_name IN ('CUSTOMER_SEGMENT','SEGMENT');" "system" | tr -d '[:space:]')
    if [ "${MV_SEG_CHECK:-0}" -gt 0 ] 2>/dev/null; then
        MV_HAS_SEGMENT="true"
    fi
fi

# ---------------------------------------------------------------
# 5. Check CSV export
# ---------------------------------------------------------------
CSV_PATH="/home/ga/Documents/exports/billing_reconciliation.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_ROWS=0
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")

    OUTPUT_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ---------------------------------------------------------------
# 6. Gather GUI usage evidence
# ---------------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# ---------------------------------------------------------------
# 7. Write result JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "function_exists": $FUNC_EXISTS,
    "func_test_flat": "$FUNC_TEST_FLAT",
    "func_test_cancel": "$FUNC_TEST_CANCEL",
    "func_test_tiered": "$FUNC_TEST_TIERED",
    "func_source_has_graduated": ${FUNC_SOURCE_HAS_GRADUATED:-false},
    "view_exists": $VIEW_EXISTS,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "distinct_disc_types": ${DISTINCT_DISC_TYPES:-0},
    "disc_types_list": "$DISC_TYPES_LIST",
    "adj_table_exists": $ADJ_TABLE_EXISTS,
    "adj_row_count": ${ADJ_ROW_COUNT:-0},
    "adj_has_required_cols": $ADJ_HAS_REQUIRED_COLS,
    "adj_has_nonzero_amounts": $ADJ_HAS_NONZERO_AMOUNTS,
    "mv_exists": $MV_EXISTS,
    "mv_row_count": ${MV_ROW_COUNT:-0},
    "mv_has_segment": $MV_HAS_SEGMENT,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": ${CSV_SIZE:-0},
    "csv_rows": ${CSV_ROWS:-0},
    "csv_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start": ${TASK_START:-0},
    ${GUI_EVIDENCE}
}
EOF

rm -f /tmp/billing_reconciliation_result.json 2>/dev/null || sudo rm -f /tmp/billing_reconciliation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/billing_reconciliation_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/billing_reconciliation_result.json
chmod 666 /tmp/billing_reconciliation_result.json 2>/dev/null || sudo chmod 666 /tmp/billing_reconciliation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/billing_reconciliation_result.json"
cat /tmp/billing_reconciliation_result.json
echo "=== Export complete ==="
