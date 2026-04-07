#!/bin/bash
# Export results for Supply Chain Inventory Rebalance task
echo "=== Exporting Supply Chain results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Sanitize: ensure a variable holds a valid integer, default to given fallback
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize all flags
DEMAND_ANALYSIS_EXISTS=false
DEMAND_ANALYSIS_ROWS=0
ZERO_REORDER_FIXED=false
EXCESSIVE_SAFETY_FIXED=false
ZERO_LEADTIME_FIXED=false
INVENTORY_FORECAST_EXISTS=false
MODEL_CLAUSE_USED=false
REBALANCE_VW_EXISTS=false
JSON_USED=false
SCHEDULER_JOB_EXISTS=false
PROC_EXISTS=false
ALERTS_TABLE_EXISTS=false
ALERT_COUNT=0
REMAINING_ZERO_REORDER=0
REMAINING_EXCESSIVE_SAFETY=0
REMAINING_ZERO_LEADTIME=0

# --- Check DEMAND_ANALYSIS table ---
DA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'SC_MANAGER' AND table_name = 'DEMAND_ANALYSIS';" "system" | tr -d '[:space:]')
if [ "${DA_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DEMAND_ANALYSIS_EXISTS=true
    DEMAND_ANALYSIS_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM sc_manager.demand_analysis;" "system" | tr -d '[:space:]')
    DEMAND_ANALYSIS_ROWS=${DEMAND_ANALYSIS_ROWS:-0}
fi

# --- Check window function usage in DEMAND_ANALYSIS or any view/procedure ---
WINDOW_FUNC_USED=false
SRC_TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'SC_MANAGER' ORDER BY name, type, line;" "system" 2>/dev/null)
if echo "$SRC_TEXT" | grep -qiE "OVER\s*\(|LAG\s*\(|LEAD\s*\(|STDDEV.*OVER|AVG.*OVER" 2>/dev/null; then
    WINDOW_FUNC_USED=true
fi

# --- Check reorder parameter fixes ---
# Error 1: Zero reorder points (originally 12 rows with reorder_point=0)
REMAINING_ZERO_REORDER=$(oracle_query_raw "SELECT COUNT(*) FROM sc_manager.inventory_params WHERE reorder_point = 0;" "system" | tr -d '[:space:]')
REMAINING_ZERO_REORDER=${REMAINING_ZERO_REORDER:-12}
if [ "${REMAINING_ZERO_REORDER:-12}" = "0" ] 2>/dev/null; then
    ZERO_REORDER_FIXED=true
fi

# Error 2: Excessive safety stock (originally 8 rows with safety_stock > avg_demand*12)
REMAINING_EXCESSIVE_SAFETY=$(oracle_query_raw "
SELECT COUNT(*) FROM sc_manager.inventory_params ip
WHERE ip.safety_stock > (
    SELECT AVG(dh.quantity_demanded) * 12
    FROM sc_manager.demand_history dh
    WHERE dh.product_id = ip.product_id AND dh.warehouse_id = ip.warehouse_id
);" "system" | tr -d '[:space:]')
REMAINING_EXCESSIVE_SAFETY=${REMAINING_EXCESSIVE_SAFETY:-8}
if [ "${REMAINING_EXCESSIVE_SAFETY:-8}" = "0" ] 2>/dev/null; then
    EXCESSIVE_SAFETY_FIXED=true
fi

# Error 3: Zero lead times (originally 5 rows with lead_time_days=0)
REMAINING_ZERO_LEADTIME=$(oracle_query_raw "SELECT COUNT(*) FROM sc_manager.inventory_params WHERE lead_time_days = 0;" "system" | tr -d '[:space:]')
REMAINING_ZERO_LEADTIME=${REMAINING_ZERO_LEADTIME:-5}
if [ "${REMAINING_ZERO_LEADTIME:-5}" = "0" ] 2>/dev/null; then
    ZERO_LEADTIME_FIXED=true
fi

# --- Check INVENTORY_FORECAST_VW ---
IF_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SC_MANAGER' AND view_name = 'INVENTORY_FORECAST_VW';" "system" | tr -d '[:space:]')
if [ "${IF_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    INVENTORY_FORECAST_EXISTS=true

    # Check for MODEL clause usage
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'SC_MANAGER' AND view_name = 'INVENTORY_FORECAST_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "\bMODEL\b" 2>/dev/null; then
        MODEL_CLAUSE_USED=true
    fi
fi

# --- Check REBALANCE_RECOMMENDATIONS_VW ---
RR_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SC_MANAGER' AND view_name = 'REBALANCE_RECOMMENDATIONS_VW';" "system" | tr -d '[:space:]')
if [ "${RR_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    REBALANCE_VW_EXISTS=true

    # Check for JSON usage
    RR_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'SC_MANAGER' AND view_name = 'REBALANCE_RECOMMENDATIONS_VW';" "system" 2>/dev/null)
    if echo "$RR_TEXT" | grep -qiE "JSON_OBJECT|JSON_ARRAY|JSON_QUERY|IS JSON" 2>/dev/null; then
        JSON_USED=true
    fi
fi

# --- Check DBMS_SCHEDULER job ---
JOB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_scheduler_jobs WHERE owner = 'SC_MANAGER' AND job_name = 'INVENTORY_MONITOR';" "system" | tr -d '[:space:]')
if [ "${JOB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SCHEDULER_JOB_EXISTS=true
fi

# --- Check stored procedure ---
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'SC_MANAGER' AND object_name = 'PROC_CHECK_STOCKOUT_RISK';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
fi

# --- Check INVENTORY_ALERTS table ---
ALERTS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'SC_MANAGER' AND table_name = 'INVENTORY_ALERTS';" "system" | tr -d '[:space:]')
if [ "${ALERTS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ALERTS_TABLE_EXISTS=true
    ALERT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM sc_manager.inventory_alerts;" "system" | tr -d '[:space:]')
    ALERT_COUNT=${ALERT_COUNT:-0}
fi

# --- Check for EOQ formula usage in any source ---
EOQ_USED=false
if echo "$SRC_TEXT" | grep -qiE "SQRT\s*\(\s*2\s*\*|EOQ|economic.order" 2>/dev/null; then
    EOQ_USED=true
fi

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Sanitize all numeric variables before JSON output
DEMAND_ANALYSIS_ROWS=$(sanitize_int "$DEMAND_ANALYSIS_ROWS" 0)
REMAINING_ZERO_REORDER=$(sanitize_int "$REMAINING_ZERO_REORDER" 12)
REMAINING_EXCESSIVE_SAFETY=$(sanitize_int "$REMAINING_EXCESSIVE_SAFETY" 8)
REMAINING_ZERO_LEADTIME=$(sanitize_int "$REMAINING_ZERO_LEADTIME" 5)
ALERT_COUNT=$(sanitize_int "$ALERT_COUNT" 0)

# --- Write result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "demand_analysis_exists": $DEMAND_ANALYSIS_EXISTS,
    "demand_analysis_rows": ${DEMAND_ANALYSIS_ROWS:-0},
    "window_functions_used": $WINDOW_FUNC_USED,
    "zero_reorder_fixed": $ZERO_REORDER_FIXED,
    "remaining_zero_reorder": ${REMAINING_ZERO_REORDER:-12},
    "excessive_safety_fixed": $EXCESSIVE_SAFETY_FIXED,
    "remaining_excessive_safety": ${REMAINING_EXCESSIVE_SAFETY:-8},
    "zero_leadtime_fixed": $ZERO_LEADTIME_FIXED,
    "remaining_zero_leadtime": ${REMAINING_ZERO_LEADTIME:-5},
    "inventory_forecast_exists": $INVENTORY_FORECAST_EXISTS,
    "model_clause_used": $MODEL_CLAUSE_USED,
    "rebalance_vw_exists": $REBALANCE_VW_EXISTS,
    "json_used": $JSON_USED,
    "scheduler_job_exists": $SCHEDULER_JOB_EXISTS,
    "stockout_proc_exists": $PROC_EXISTS,
    "alerts_table_exists": $ALERTS_TABLE_EXISTS,
    "alert_count": ${ALERT_COUNT:-0},
    "eoq_used": $EOQ_USED,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/supply_chain_result.json 2>/dev/null || sudo rm -f /tmp/supply_chain_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/supply_chain_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/supply_chain_result.json
chmod 666 /tmp/supply_chain_result.json 2>/dev/null || sudo chmod 666 /tmp/supply_chain_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/supply_chain_result.json"
cat /tmp/supply_chain_result.json
echo "=== Export complete ==="
