#!/bin/bash
# Export results for Carrier Delay Pattern Analysis task
echo "=== Exporting Carrier Delay Pattern Analysis results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize metrics
CONSECUTIVE_VIEW_EXISTS=false
MATCH_RECOGNIZE_USED=false
PATTERN_COUNT=0

SCORECARDS_VIEW_EXISTS=false
WINDOW_FUNC_USED=false

BOTTLENECK_VIEW_EXISTS=false
BOTTLENECK_FOUND=false

AT_RISK_TABLE_EXISTS=false
AT_RISK_ROW_COUNT=0
PROC_EXISTS=false

PIVOT_VIEW_EXISTS=false
PIVOT_USED=false

CSV_EXISTS=false
CSV_SIZE=0
CSV_HAS_DATA=false

# 1. Check CONSECUTIVE_DELAY_PATTERNS
VIEW1_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'LOGISTICS_ANALYST' AND view_name = 'CONSECUTIVE_DELAY_PATTERNS';" "system" | tr -d '[:space:]')
if [ "${VIEW1_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CONSECUTIVE_VIEW_EXISTS=true
    VIEW1_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'LOGISTICS_ANALYST' AND view_name = 'CONSECUTIVE_DELAY_PATTERNS';" "system" 2>/dev/null)
    if echo "$VIEW1_TEXT" | grep -qiE "MATCH_RECOGNIZE"; then
        MATCH_RECOGNIZE_USED=true
    fi
    PATTERN_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM logistics_analyst.consecutive_delay_patterns;" "system" | tr -d '[:space:]' || echo "0")
    if ! [[ "$PATTERN_COUNT" =~ ^[0-9]+$ ]]; then PATTERN_COUNT=0; fi
fi

# 2. Check CARRIER_SCORECARDS
VIEW2_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'LOGISTICS_ANALYST' AND view_name = 'CARRIER_SCORECARDS';" "system" | tr -d '[:space:]')
if [ "${VIEW2_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SCORECARDS_VIEW_EXISTS=true
    VIEW2_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'LOGISTICS_ANALYST' AND view_name = 'CARRIER_SCORECARDS';" "system" 2>/dev/null)
    if echo "$VIEW2_TEXT" | grep -qiE "OVER\s*\("; then
        WINDOW_FUNC_USED=true
    fi
fi

# 3. Check ROUTE_BOTTLENECK_ANALYSIS
VIEW3_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'LOGISTICS_ANALYST' AND view_name = 'ROUTE_BOTTLENECK_ANALYSIS';" "system" | tr -d '[:space:]')
if [ "${VIEW3_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    BOTTLENECK_VIEW_EXISTS=true
    # Check if Dallas->Houston route (202) is detected
    B_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM logistics_analyst.route_bottleneck_analysis WHERE route_id = 202 OR origin_city LIKE '%Dallas%';" "system" | tr -d '[:space:]' || echo "0")
    if [ "${B_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        BOTTLENECK_FOUND=true
    fi
fi

# 4. Check AT_RISK_SHIPMENTS & PROC_FLAG_AT_RISK_SHIPMENTS
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'LOGISTICS_ANALYST' AND table_name = 'AT_RISK_SHIPMENTS';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    AT_RISK_TABLE_EXISTS=true
    AT_RISK_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM logistics_analyst.at_risk_shipments;" "system" | tr -d '[:space:]' || echo "0")
    if ! [[ "$AT_RISK_ROW_COUNT" =~ ^[0-9]+$ ]]; then AT_RISK_ROW_COUNT=0; fi
fi

PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'LOGISTICS_ANALYST' AND object_name = 'PROC_FLAG_AT_RISK_SHIPMENTS';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
fi

# 5. Check CARRIER_COMPARISON_PIVOT
VIEW4_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'LOGISTICS_ANALYST' AND view_name = 'CARRIER_COMPARISON_PIVOT';" "system" | tr -d '[:space:]')
if [ "${VIEW4_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PIVOT_VIEW_EXISTS=true
    VIEW4_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'LOGISTICS_ANALYST' AND view_name = 'CARRIER_COMPARISON_PIVOT';" "system" 2>/dev/null)
    if echo "$VIEW4_TEXT" | grep -qiE "\bPIVOT\b"; then
        PIVOT_USED=true
    fi
fi

# 6. Check CSV File
CSV_PATH="/home/ga/carrier_performance.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_SIZE" -gt 50 ]; then
        CSV_HAS_DATA=true
    fi
fi

# GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "consecutive_view_exists": $CONSECUTIVE_VIEW_EXISTS,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "pattern_count": $PATTERN_COUNT,
    "scorecards_view_exists": $SCORECARDS_VIEW_EXISTS,
    "window_func_used": $WINDOW_FUNC_USED,
    "bottleneck_view_exists": $BOTTLENECK_VIEW_EXISTS,
    "bottleneck_found": $BOTTLENECK_FOUND,
    "at_risk_table_exists": $AT_RISK_TABLE_EXISTS,
    "at_risk_row_count": $AT_RISK_ROW_COUNT,
    "proc_exists": $PROC_EXISTS,
    "pivot_view_exists": $PIVOT_VIEW_EXISTS,
    "pivot_used": $PIVOT_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_has_data": $CSV_HAS_DATA,
    $GUI_EVIDENCE
}
EOF

rm -f /tmp/carrier_delay_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/carrier_delay_result.json
chmod 666 /tmp/carrier_delay_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="