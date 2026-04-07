#!/bin/bash
echo "=== Exporting Hotel Revenue Cancellation Analytics Results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png ga

# Fetch GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Initialize defaults
PROC_EXISTS=false
INVALID_RECORDS_REMAINING=999
CUBE_VW_EXISTS=false
CUBE_USED=false
PERCENTILE_VW_EXISTS=false
PERCENTILE_USED=false
PIVOT_VW_EXISTS=false
PIVOT_USED=false
PIVOT_COLS_CORRECT=false
CSV_EXISTS=false
CSV_SIZE=0

# 1. Check Data Cleansing
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'REVENUE_ANALYST' AND object_name = 'PROC_CLEANSE_BOOKINGS';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
fi

INVALID_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM revenue_analyst.hotel_bookings WHERE (adults+children+babies)=0 OR adr<0;" "system" | tr -d '[:space:]')
if [[ "$INVALID_COUNT" =~ ^[0-9]+$ ]]; then
    INVALID_RECORDS_REMAINING=$INVALID_COUNT
fi

# 2. Check Cancellation Cube
CUBE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'REVENUE_ANALYST' AND view_name = 'CANCELLATION_CUBE_VW';" "system" | tr -d '[:space:]')
if [ "${CUBE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CUBE_VW_EXISTS=true
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'REVENUE_ANALYST' AND view_name = 'CANCELLATION_CUBE_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "\bCUBE\b"; then
        CUBE_USED=true
    fi
fi

# 3. Check ADR Percentiles
PERCENTILE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'REVENUE_ANALYST' AND view_name = 'ADR_PERCENTILES_VW';" "system" | tr -d '[:space:]')
if [ "${PERCENTILE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PERCENTILE_VW_EXISTS=true
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'REVENUE_ANALYST' AND view_name = 'ADR_PERCENTILES_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "PERCENTILE_CONT"; then
        PERCENTILE_USED=true
    fi
fi

# 4. Check Lost Revenue Pivot
PIVOT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'REVENUE_ANALYST' AND view_name = 'LOST_REVENUE_PIVOT_VW';" "system" | tr -d '[:space:]')
if [ "${PIVOT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PIVOT_VW_EXISTS=true
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'REVENUE_ANALYST' AND view_name = 'LOST_REVENUE_PIVOT_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "\bPIVOT\b"; then
        PIVOT_USED=true
    fi
    
    # Check for specific aliased columns
    COLS=$(oracle_query_raw "SELECT column_name FROM all_tab_cols WHERE owner = 'REVENUE_ANALYST' AND table_name = 'LOST_REVENUE_PIVOT_VW';" "system" 2>/dev/null)
    if echo "$COLS" | grep -qi "no_deposit" && echo "$COLS" | grep -qi "non_refund" && echo "$COLS" | grep -qi "refundable"; then
        PIVOT_COLS_CORRECT=true
    fi
fi

# 5. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/lost_revenue.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "proc_exists": $PROC_EXISTS,
    "invalid_records_remaining": $INVALID_RECORDS_REMAINING,
    "cube_vw_exists": $CUBE_VW_EXISTS,
    "cube_used": $CUBE_USED,
    "percentile_vw_exists": $PERCENTILE_VW_EXISTS,
    "percentile_used": $PERCENTILE_USED,
    "pivot_vw_exists": $PIVOT_VW_EXISTS,
    "pivot_used": $PIVOT_USED,
    "pivot_cols_correct": $PIVOT_COLS_CORRECT,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    $GUI_EVIDENCE
}
EOF

# Move securely
rm -f /tmp/hotel_revenue_result.json 2>/dev/null || sudo rm -f /tmp/hotel_revenue_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hotel_revenue_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hotel_revenue_result.json
chmod 666 /tmp/hotel_revenue_result.json 2>/dev/null || sudo chmod 666 /tmp/hotel_revenue_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/hotel_revenue_result.json"
cat /tmp/hotel_revenue_result.json
echo "=== Export Complete ==="