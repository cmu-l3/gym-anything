#!/bin/bash
echo "=== Exporting Actuarial Loss Reserve Triangulation Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png ga

# Check Triangle View
TRIANGLE_VW_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ACTUARY_ADMIN' AND view_name = 'COMPANY_TRIANGLE_VW';" "system" | tr -d '[:space:]')
if [ "${TRIANGLE_VW_EXISTS:-0}" -gt 0 ] 2>/dev/null; then
    TRIANGLE_VW_EXISTS="true"
    COLS=$(oracle_query_raw "SELECT column_name FROM all_tab_cols WHERE owner = 'ACTUARY_ADMIN' AND table_name = 'COMPANY_TRIANGLE_VW' AND column_name LIKE 'DLAG_%' ORDER BY column_name;" "system" | tr '\n' ',' | sed 's/,$//')
else
    TRIANGLE_VW_EXISTS="false"
    COLS=""
fi

# Check Link Ratios View and Agent Output
LINK_RATIOS_VW_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ACTUARY_ADMIN' AND view_name = 'COMPANY_LINK_RATIOS_VW';" "system" | tr -d '[:space:]')
if [ "${LINK_RATIOS_VW_EXISTS:-0}" -gt 0 ] 2>/dev/null; then
    LINK_RATIOS_VW_EXISTS="true"
    # Format to 4 decimals using TO_CHAR to standardize leading/trailing zeroes for reliable comparison
    LINK_DATA=$(oracle_query_raw "SELECT accident_year || '_' || target_lag || '_' || TO_CHAR(ROUND(link_ratio, 4), 'FM9990.0000') FROM actuary_admin.company_link_ratios_vw WHERE accident_year = 2021 AND target_lag IN (2,3) ORDER BY target_lag;" "system" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
else
    LINK_RATIOS_VW_EXISTS="false"
    LINK_DATA=""
fi

# Ground Truth for Link Ratios
GT_LINK_DATA=$(oracle_query_raw "
WITH lagged AS (
  SELECT accident_year, development_lag as target_lag, cumulative_paid_loss as loss_curr,
         LAG(cumulative_paid_loss) OVER (PARTITION BY accident_year ORDER BY development_lag) as loss_prev,
         LAG(development_lag) OVER (PARTITION BY accident_year ORDER BY development_lag) as prev_lag
  FROM actuary_admin.schedule_p_raw
  WHERE line_of_business = 'Commercial Auto' AND group_code = '1767'
)
SELECT accident_year || '_' || target_lag || '_' || TO_CHAR(ROUND(loss_curr / loss_prev, 4), 'FM9990.0000')
FROM lagged
WHERE target_lag = prev_lag + 1 AND accident_year = 2021 AND target_lag IN (2,3)
ORDER BY target_lag;
" "system" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Check Industry Benchmarks View and Agent Output
LDF_VW_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ACTUARY_ADMIN' AND view_name = 'INDUSTRY_LDF_BENCHMARKS_VW';" "system" | tr -d '[:space:]')
if [ "${LDF_VW_EXISTS:-0}" -gt 0 ] 2>/dev/null; then
    LDF_VW_EXISTS="true"
    # Again, robustly cast to exactly 4 decimals to compare with ground truth 
    AGENT_LDF_DATA=$(oracle_query_raw "SELECT target_lag || '_' || TO_CHAR(ROUND(volume_weighted_ldf, 4), 'FM9990.0000') FROM actuary_admin.industry_ldf_benchmarks_vw ORDER BY target_lag;" "system" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
else
    LDF_VW_EXISTS="false"
    AGENT_LDF_DATA=""
fi

# Ground Truth for Volume-Weighted LDF (this will natively exclude the missing lag 3 for 3000 cohort)
GT_LDF_DATA=$(oracle_query_raw "
WITH lagged AS (
  SELECT group_code, accident_year, development_lag as target_lag, cumulative_paid_loss as loss_curr,
         LAG(cumulative_paid_loss) OVER (PARTITION BY group_code, accident_year ORDER BY development_lag) as loss_prev,
         LAG(development_lag) OVER (PARTITION BY group_code, accident_year ORDER BY development_lag) as prev_lag
  FROM actuary_admin.schedule_p_raw
  WHERE line_of_business = 'Commercial Auto'
)
SELECT target_lag || '_' || TO_CHAR(ROUND(SUM(loss_curr) / SUM(loss_prev), 4), 'FM9990.0000')
FROM lagged
WHERE target_lag = prev_lag + 1
GROUP BY target_lag
ORDER BY target_lag;
" "system" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Check CSV Export
CSV_PATH="/home/ga/Documents/exports/industry_ldf_benchmarks.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
else
    CSV_EXISTS="false"
    CSV_SIZE="0"
fi

GUI_EVIDENCE=$(collect_gui_evidence)

TEMP_JSON=$(mktemp /tmp/actuary_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "triangle_vw_exists": $TRIANGLE_VW_EXISTS,
    "triangle_cols": "$COLS",
    "link_ratios_vw_exists": $LINK_RATIOS_VW_EXISTS,
    "link_data": "$LINK_DATA",
    "gt_link_data": "$GT_LINK_DATA",
    "ldf_vw_exists": $LDF_VW_EXISTS,
    "agent_ldf_data": "$AGENT_LDF_DATA",
    "gt_ldf_data": "$GT_LDF_DATA",
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

rm -f /tmp/actuary_result.json 2>/dev/null || sudo rm -f /tmp/actuary_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/actuary_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/actuary_result.json
chmod 666 /tmp/actuary_result.json 2>/dev/null || sudo chmod 666 /tmp/actuary_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/actuary_result.json"
echo "Export complete."