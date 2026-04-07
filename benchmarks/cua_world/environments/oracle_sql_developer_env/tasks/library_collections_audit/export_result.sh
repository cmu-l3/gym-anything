#!/bin/bash
# Export results for Library Collections Audit task
echo "=== Exporting Library Collections Audit Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Helper function to parse numbers safely from oracle output
safe_num() {
    local val="$1"
    if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$val"
    else
        echo "-1"
    fi
}

# 1. Weeding List View
WEED_VW_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='LIBRARY_ADMIN' AND view_name='WEEDING_LIST_VW';" "system" | tr -d '[:space:]')
WEEDING_COUNT=-1
if [ "$WEED_VW_EXISTS" = "1" ]; then
    RES=$(oracle_query_raw "SELECT COUNT(*) FROM library_admin.weeding_list_vw;" "system" | tr -d '[:space:]')
    WEEDING_COUNT=$(safe_num "$RES")
fi

# 2. Purchase Recommendations View
PURCHASE_VW_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='LIBRARY_ADMIN' AND view_name='PURCHASE_RECOMMENDATIONS_VW';" "system" | tr -d '[:space:]')
PURCHASE_COUNT=-1
PURCHASE_BIB_SUM=-1
if [ "$PURCHASE_VW_EXISTS" = "1" ]; then
    RES1=$(oracle_query_raw "SELECT COUNT(*) FROM library_admin.purchase_recommendations_vw;" "system" | tr -d '[:space:]')
    PURCHASE_COUNT=$(safe_num "$RES1")
    RES2=$(oracle_query_raw "SELECT SUM(bib_num) FROM library_admin.purchase_recommendations_vw;" "system" | tr -d '[:space:]')
    PURCHASE_BIB_SUM=$(safe_num "$RES2")
fi

# 3. Phantom Holds Log
PHANTOM_TBL_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='LIBRARY_ADMIN' AND table_name='PHANTOM_HOLDS_LOG';" "system" | tr -d '[:space:]')
PHANTOM_COUNT=-1
PHANTOM_HOLD_SUM=-1
if [ "$PHANTOM_TBL_EXISTS" = "1" ]; then
    RES1=$(oracle_query_raw "SELECT COUNT(*) FROM library_admin.phantom_holds_log;" "system" | tr -d '[:space:]')
    PHANTOM_COUNT=$(safe_num "$RES1")
    RES2=$(oracle_query_raw "SELECT SUM(hold_id) FROM library_admin.phantom_holds_log;" "system" | tr -d '[:space:]')
    PHANTOM_HOLD_SUM=$(safe_num "$RES2")
fi

# 4. Collection Turnover MV
TURNOVER_MV_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='LIBRARY_ADMIN' AND mview_name='COLLECTION_TURNOVER_MV';" "system" | tr -d '[:space:]')
TURNOVER_COUNT=-1
TURNOVER_800=-1
if [ "$TURNOVER_MV_EXISTS" = "1" ]; then
    RES1=$(oracle_query_raw "SELECT COUNT(*) FROM library_admin.collection_turnover_mv;" "system" | tr -d '[:space:]')
    TURNOVER_COUNT=$(safe_num "$RES1")
    RES2=$(oracle_query_raw "SELECT turnover_rate FROM library_admin.collection_turnover_mv WHERE dewey_category = '800s';" "system" | tr -d '[:space:]')
    TURNOVER_800=$(safe_num "$RES2")
fi

# 5. CSV Export
CSV_EXISTS="false"
CSV_SIZE=0
CSV_ROWS=0
if [ -f "/home/ga/Documents/exports/purchase_recs.csv" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "/home/ga/Documents/exports/purchase_recs.csv")
    CSV_ROWS=$(wc -l < "/home/ga/Documents/exports/purchase_recs.csv")
fi

# Generate JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "weeding_vw_exists": $([ "$WEED_VW_EXISTS" = "1" ] && echo "true" || echo "false"),
    "weeding_count": $WEEDING_COUNT,
    "purchase_vw_exists": $([ "$PURCHASE_VW_EXISTS" = "1" ] && echo "true" || echo "false"),
    "purchase_count": $PURCHASE_COUNT,
    "purchase_bib_sum": $PURCHASE_BIB_SUM,
    "phantom_tbl_exists": $([ "$PHANTOM_TBL_EXISTS" = "1" ] && echo "true" || echo "false"),
    "phantom_count": $PHANTOM_COUNT,
    "phantom_hold_sum": $PHANTOM_HOLD_SUM,
    "turnover_mv_exists": $([ "$TURNOVER_MV_EXISTS" = "1" ] && echo "true" || echo "false"),
    "turnover_count": $TURNOVER_COUNT,
    "turnover_800": $TURNOVER_800,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_rows": $CSV_ROWS,
    ${GUI_EVIDENCE}
}
EOF

# Move securely
sudo mv "$TEMP_JSON" /tmp/library_result.json
sudo chmod 666 /tmp/library_result.json

cat /tmp/library_result.json
echo "=== Export Complete ==="