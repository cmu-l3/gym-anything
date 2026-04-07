#!/bin/bash
# Export results for Grocery Market Basket Analysis task
echo "=== Exporting Grocery Market Basket results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize flags
PRODUCT_VW_EXISTS="false"
PAIR_VW_EXISTS="false"
MV_EXISTS="false"
FILTER_FAILS=999
HD_STATS=""
PBJ_STATS=""
CSV_EXISTS="false"
CSV_LINES=0
FILE_CREATED_DURING_TASK="false"

# 1. Check Views
PVW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='GROCERY_BI' AND view_name='PRODUCT_METRICS_VW';" "system" | tr -d '[:space:]')
if [ "${PVW_CHECK:-0}" -gt 0 ] 2>/dev/null; then PRODUCT_VW_EXISTS="true"; fi

PAIR_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='GROCERY_BI' AND view_name='PAIR_METRICS_VW';" "system" | tr -d '[:space:]')
if [ "${PAIR_CHECK:-0}" -gt 0 ] 2>/dev/null; then PAIR_VW_EXISTS="true"; fi

# 2. Check MV
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='GROCERY_BI' AND mview_name='MARKET_BASKET_RULES_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then MV_EXISTS="true"; fi

# 3. Check Math and Filtering
if [ "$MV_EXISTS" = "true" ]; then
    # Verify filters (should be 0)
    FILTER_FAILS=$(oracle_query_raw "SELECT COUNT(*) FROM GROCERY_BI.MARKET_BASKET_RULES_MV WHERE pair_order_count < 20 OR lift <= 2;" "system" | tr -d '[:space:]')
    
    # Verify Hot Dogs & Buns
    HD_STATS=$(oracle_query_raw "SELECT pair_order_count || ',' || ROUND(confidence_a_to_b, 4) || ',' || ROUND(confidence_b_to_a, 4) || ',' || ROUND(lift, 4) FROM GROCERY_BI.MARKET_BASKET_RULES_MV WHERE product_a_name='Hot Dogs' AND product_b_name='Hot Dog Buns';" "system")
    
    # Verify PB & Jelly
    PBJ_STATS=$(oracle_query_raw "SELECT pair_order_count || ',' || ROUND(confidence_a_to_b, 4) || ',' || ROUND(confidence_b_to_a, 4) || ',' || ROUND(lift, 4) FROM GROCERY_BI.MARKET_BASKET_RULES_MV WHERE product_a_name='Peanut Butter' AND product_b_name='Jelly';" "system")
fi

# 4. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/market_basket_top200.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_LINES=$(wc -l < "$CSV_PATH" | tr -d '[:space:]')
    
    # Check creation time for anti-gaming
    OUTPUT_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "product_vw_exists": $PRODUCT_VW_EXISTS,
    "pair_vw_exists": $PAIR_VW_EXISTS,
    "mv_exists": $MV_EXISTS,
    "filter_fails": ${FILTER_FAILS:-999},
    "hd_stats": "$HD_STATS",
    "pbj_stats": "$PBJ_STATS",
    "csv_exists": $CSV_EXISTS,
    "csv_lines": $CSV_LINES,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/grocery_result.json 2>/dev/null || sudo rm -f /tmp/grocery_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/grocery_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/grocery_result.json
chmod 666 /tmp/grocery_result.json 2>/dev/null || sudo chmod 666 /tmp/grocery_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/grocery_result.json"
cat /tmp/grocery_result.json
echo "=== Export complete ==="