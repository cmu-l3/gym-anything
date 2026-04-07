#!/bin/bash
# Export results for BOM Cost Explosion Analysis task
echo "=== Exporting BOM Analysis results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize flags
CYCLES_FIXED=false
REMAINING_CYCLES=0
FIX_LOG_EXISTS=false
FIX_LOG_COUNT=0
EXPLOSION_VW_EXISTS=false
EXPLOSION_CONNECT_USED=false
EXPLOSION_PATH_USED=false
WHERE_USED_EXISTS=false
WHERE_USED_CONNECT_USED=false
MRP_PROC_EXISTS=false
MRP_REQ_TABLE_EXISTS=false
MRP_REQ_ROWS=0
WS5000_REQUIREMENTS=0
COST_SUMMARY_MV_EXISTS=false
ROLLUP_USED=false
CSV_EXISTS=false
CSV_SIZE=0

# 1. Check remaining circular references
# Use CONNECT BY NOCYCLE to safely count remaining cycles without crashing
REMAINING_CYCLES=$(oracle_query_raw "
SELECT COUNT(*) FROM mfg_engineer.bom_lines bl
WHERE CONNECT_BY_ISCYCLE = 1
START WITH parent_item_id = 1
CONNECT BY NOCYCLE PRIOR component_item_id = parent_item_id;" "system" | tr -d '[:space:]')
REMAINING_CYCLES=${REMAINING_CYCLES:-99}

if [ "$REMAINING_CYCLES" = "0" ] 2>/dev/null; then
    CYCLES_FIXED=true
fi

# 2. Check BOM_FIXES_LOG table
LOG_TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'MFG_ENGINEER' AND table_name = 'BOM_FIXES_LOG';" "system" | tr -d '[:space:]')
if [ "${LOG_TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FIX_LOG_EXISTS=true
    FIX_LOG_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM mfg_engineer.bom_fixes_log;" "system" | tr -d '[:space:]')
    FIX_LOG_COUNT=${FIX_LOG_COUNT:-0}
fi

# 3. Check COSTED_BOM_EXPLOSION_VW
EXPL_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MFG_ENGINEER' AND view_name = 'COSTED_BOM_EXPLOSION_VW';" "system" | tr -d '[:space:]')
if [ "${EXPL_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    EXPLOSION_VW_EXISTS=true
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'MFG_ENGINEER' AND view_name = 'COSTED_BOM_EXPLOSION_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "CONNECT\s*BY" 2>/dev/null; then
        EXPLOSION_CONNECT_USED=true
    fi
    if echo "$VW_TEXT" | grep -qiE "SYS_CONNECT_BY_PATH" 2>/dev/null; then
        EXPLOSION_PATH_USED=true
    fi
fi

# 4. Check WHERE_USED_VW
WU_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'MFG_ENGINEER' AND view_name = 'WHERE_USED_VW';" "system" | tr -d '[:space:]')
if [ "${WU_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    WHERE_USED_EXISTS=true
    WU_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'MFG_ENGINEER' AND view_name = 'WHERE_USED_VW';" "system" 2>/dev/null)
    if echo "$WU_TEXT" | grep -qiE "CONNECT\s*BY" 2>/dev/null; then
        WHERE_USED_CONNECT_USED=true
    fi
fi

# 5. Check PROC_CALC_MRP and MRP_REQUIREMENTS table
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'MFG_ENGINEER' AND object_name = 'PROC_CALC_MRP';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MRP_PROC_EXISTS=true
fi

REQ_TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'MFG_ENGINEER' AND table_name = 'MRP_REQUIREMENTS';" "system" | tr -d '[:space:]')
if [ "${REQ_TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MRP_REQ_TABLE_EXISTS=true
    MRP_REQ_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM mfg_engineer.mrp_requirements;" "system" | tr -d '[:space:]')
    MRP_REQ_ROWS=${MRP_REQ_ROWS:-0}
    
    # Check if WS-5000 (item_id 1) was run
    WS5000_REQUIREMENTS=$(oracle_query_raw "SELECT COUNT(*) FROM mfg_engineer.mrp_requirements WHERE product_id = 1;" "system" | tr -d '[:space:]')
    WS5000_REQUIREMENTS=${WS5000_REQUIREMENTS:-0}
fi

# 6. Check BOM_COST_SUMMARY_MV
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'MFG_ENGINEER' AND mview_name = 'BOM_COST_SUMMARY_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    COST_SUMMARY_MV_EXISTS=true
    
    # Check for ROLLUP usage in text
    MV_TEXT=$(oracle_query_raw "SELECT query FROM all_mviews WHERE owner = 'MFG_ENGINEER' AND mview_name = 'BOM_COST_SUMMARY_MV';" "system" 2>/dev/null)
    if echo "$MV_TEXT" | grep -qiE "\bROLLUP\b|\bCUBE\b" 2>/dev/null; then
        ROLLUP_USED=true
    fi
fi

# 7. Check CSV export
CSV_PATH="/home/ga/bom_mrp_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 8. Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export to JSON
TEMP_JSON=$(mktemp /tmp/bom_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cycles_fixed": $CYCLES_FIXED,
    "remaining_cycles": $REMAINING_CYCLES,
    "fix_log_exists": $FIX_LOG_EXISTS,
    "fix_log_count": $FIX_LOG_COUNT,
    "explosion_vw_exists": $EXPLOSION_VW_EXISTS,
    "explosion_connect_used": $EXPLOSION_CONNECT_USED,
    "explosion_path_used": $EXPLOSION_PATH_USED,
    "where_used_exists": $WHERE_USED_EXISTS,
    "where_used_connect_used": $WHERE_USED_CONNECT_USED,
    "mrp_proc_exists": $MRP_PROC_EXISTS,
    "mrp_req_table_exists": $MRP_REQ_TABLE_EXISTS,
    "mrp_req_rows": $MRP_REQ_ROWS,
    "ws5000_requirements": $WS5000_REQUIREMENTS,
    "cost_summary_mv_exists": $COST_SUMMARY_MV_EXISTS,
    "rollup_used": $ROLLUP_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Move to final location safely
rm -f /tmp/bom_result.json 2>/dev/null || sudo rm -f /tmp/bom_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bom_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bom_result.json
chmod 666 /tmp/bom_result.json 2>/dev/null || sudo chmod 666 /tmp/bom_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/bom_result.json"
cat /tmp/bom_result.json
echo "=== Export Complete ==="