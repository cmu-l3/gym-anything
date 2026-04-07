#!/bin/bash
# Export results for Credit Card Rewards FIFO Liability task
echo "=== Exporting FIFO Liability results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize output JSON template
TEMP_JSON=$(mktemp /tmp/fifo_result.XXXXXX.json)

# ==============================================================================
# 1. CALCULATE GROUND TRUTH (Independent of Agent's Code)
# ==============================================================================
echo "Calculating ground truth metrics..."

# Secure ground truth query evaluating FIFO logic for all customers
GT_QUERY="
WITH EarnRunning AS (
    SELECT cust_id, earn_id, points_amount, expire_date,
           NVL(SUM(points_amount) OVER (PARTITION BY cust_id ORDER BY transaction_date, earn_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) as prev_running
    FROM rewards_admin.earn_events
),
RedeemTotal AS (
    SELECT cust_id, NVL(SUM(points_redeemed), 0) as total_redeemed
    FROM rewards_admin.redemption_events
    GROUP BY cust_id
),
CalculatedRemaining AS (
    SELECT e.cust_id, e.earn_id, e.expire_date,
           GREATEST(0, e.points_amount - GREATEST(0, NVL(r.total_redeemed, 0) - e.prev_running)) as remaining_points
    FROM EarnRunning e LEFT JOIN RedeemTotal r ON e.cust_id = r.cust_id
)
SELECT 
    SUM(remaining_points) AS total_remaining,
    SUM(CASE WHEN expire_date <= DATE '2024-12-31' THEN remaining_points ELSE 0 END) AS total_expired,
    SUM(CASE WHEN expire_date > DATE '2024-12-31' THEN remaining_points * 0.0125 ELSE 0 END) AS total_liability
FROM CalculatedRemaining;
"

GT_OUTPUT=$(oracle_query_raw "$GT_QUERY" "system")
GT_TOTAL_REMAINING=$(echo "$GT_OUTPUT" | awk '{print $1}')
GT_TOTAL_EXPIRED=$(echo "$GT_OUTPUT" | awk '{print $2}')
GT_TOTAL_LIABILITY=$(echo "$GT_OUTPUT" | awk '{print $3}')

# Fallbacks if query fails
GT_TOTAL_REMAINING=${GT_TOTAL_REMAINING:-0}
GT_TOTAL_EXPIRED=${GT_TOTAL_EXPIRED:-0}
GT_TOTAL_LIABILITY=${GT_TOTAL_LIABILITY:-0}

# ==============================================================================
# 2. EVALUATE AGENT'S VIEW (VW_FIFO_POINT_BALANCES)
# ==============================================================================
VIEW_EXISTS="false"
AGENT_TOTAL_REMAINING=0

VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'REWARDS_ADMIN' AND view_name = 'VW_FIFO_POINT_BALANCES';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIEW_EXISTS="true"
    AGENT_TOTAL_REMAINING=$(oracle_query_raw "SELECT NVL(SUM(remaining_points), 0) FROM rewards_admin.vw_fifo_point_balances;" "system" | tr -d '[:space:]')
    AGENT_TOTAL_REMAINING=${AGENT_TOTAL_REMAINING:-0}
fi

# ==============================================================================
# 3. EVALUATE AGENT'S PROCEDURE & EXPIRATION LOG
# ==============================================================================
PROC_EXISTS="false"
AGENT_TOTAL_EXPIRED=0

PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'REWARDS_ADMIN' AND object_name = 'PROC_EXPIRE_POINTS';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS="true"
fi

AGENT_TOTAL_EXPIRED=$(oracle_query_raw "SELECT NVL(SUM(points_expired), 0) FROM rewards_admin.expired_points_log;" "system" | tr -d '[:space:]')
AGENT_TOTAL_EXPIRED=${AGENT_TOTAL_EXPIRED:-0}

# ==============================================================================
# 4. EVALUATE AGENT'S LIABILITY MV (REWARDS_LIABILITY_MV)
# ==============================================================================
MV_EXISTS="false"
AGENT_TOTAL_LIABILITY=0

MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'REWARDS_ADMIN' AND mview_name = 'REWARDS_LIABILITY_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MV_EXISTS="true"
    AGENT_TOTAL_LIABILITY=$(oracle_query_raw "SELECT NVL(SUM(financial_liability), 0) FROM rewards_admin.rewards_liability_mv;" "system" | tr -d '[:space:]')
    AGENT_TOTAL_LIABILITY=${AGENT_TOTAL_LIABILITY:-0}
fi

# ==============================================================================
# 5. COLLECT GUI TELEMETRY
# ==============================================================================
GUI_EVIDENCE=$(collect_gui_evidence)

# ==============================================================================
# 6. WRITE JSON OUTPUT
# ==============================================================================
cat > "$TEMP_JSON" << EOF
{
    "ground_truth": {
        "total_remaining": $GT_TOTAL_REMAINING,
        "total_expired": $GT_TOTAL_EXPIRED,
        "total_liability": $GT_TOTAL_LIABILITY
    },
    "agent_results": {
        "view_exists": $VIEW_EXISTS,
        "total_remaining": $AGENT_TOTAL_REMAINING,
        "proc_exists": $PROC_EXISTS,
        "total_expired": $AGENT_TOTAL_EXPIRED,
        "mv_exists": $MV_EXISTS,
        "total_liability": $AGENT_TOTAL_LIABILITY
    },
    $GUI_EVIDENCE,
    "export_timestamp": "$(date +%s)"
}
EOF

# Make readable to verifier
rm -f /tmp/rewards_liability_result.json 2>/dev/null || sudo rm -f /tmp/rewards_liability_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rewards_liability_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rewards_liability_result.json
chmod 666 /tmp/rewards_liability_result.json 2>/dev/null || sudo chmod 666 /tmp/rewards_liability_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/rewards_liability_result.json"
cat /tmp/rewards_liability_result.json
echo "=== Export Complete ==="