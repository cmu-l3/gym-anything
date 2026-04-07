#!/bin/bash
# Export results for Energy Portfolio Milestone Tracker task
echo "=== Exporting Energy Portfolio results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Sanitize: ensure a variable holds a valid integer, default to given fallback
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize all flags
MILESTONES_FIXED=0
HIERARCHY_VW_EXISTS=false
PIVOT_VW_EXISTS=false
SCHEDULER_JOB_EXISTS=false
PROC_EXISTS=false
ALERTS_TABLE_EXISTS=false
CONSTRAINT_EXISTS=false
TOTAL_VIOLATIONS=0

# --- Check milestone sequence violations ---
# A violation means a milestone with higher order has an earlier actual_date than a lower-order one
# For each project, check if milestones are in chronological order
TOTAL_VIOLATIONS=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT m1.project_id, m1.milestone_name AS early_name, m2.milestone_name AS late_name
    FROM energy_mgr.milestones m1
    JOIN energy_mgr.milestones m2 ON m1.project_id = m2.project_id
    WHERE m1.milestone_order < m2.milestone_order
    AND m1.actual_date IS NOT NULL AND m2.actual_date IS NOT NULL
    AND m1.actual_date > m2.actual_date
);" "system" | tr -d '[:space:]')
TOTAL_VIOLATIONS=${TOTAL_VIOLATIONS:-99}

# Count how many of the 4 contaminated projects are now fixed
SHEPHERDS_FLAT_OK=false
ALTA_WIND_OK=false
ROSCOE_OK=false
HORSE_HOLLOW_OK=false

# Check Shepherds Flat (project_id=1 presumably)
SF_VIOLATIONS=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT m1.milestone_name
    FROM energy_mgr.milestones m1
    JOIN energy_mgr.milestones m2 ON m1.project_id = m2.project_id
    WHERE m1.project_id = (SELECT project_id FROM energy_mgr.projects WHERE project_name LIKE '%Shepherds Flat%')
    AND m1.milestone_order < m2.milestone_order
    AND m1.actual_date IS NOT NULL AND m2.actual_date IS NOT NULL
    AND m1.actual_date > m2.actual_date
);" "system" | tr -d '[:space:]')
if [ "${SF_VIOLATIONS:-1}" = "0" ] 2>/dev/null; then
    SHEPHERDS_FLAT_OK=true
    MILESTONES_FIXED=$((MILESTONES_FIXED + 1))
fi

AW_VIOLATIONS=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT m1.milestone_name
    FROM energy_mgr.milestones m1
    JOIN energy_mgr.milestones m2 ON m1.project_id = m2.project_id
    WHERE m1.project_id = (SELECT project_id FROM energy_mgr.projects WHERE project_name LIKE '%Alta Wind%')
    AND m1.milestone_order < m2.milestone_order
    AND m1.actual_date IS NOT NULL AND m2.actual_date IS NOT NULL
    AND m1.actual_date > m2.actual_date
);" "system" | tr -d '[:space:]')
if [ "${AW_VIOLATIONS:-1}" = "0" ] 2>/dev/null; then
    ALTA_WIND_OK=true
    MILESTONES_FIXED=$((MILESTONES_FIXED + 1))
fi

RO_VIOLATIONS=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT m1.milestone_name
    FROM energy_mgr.milestones m1
    JOIN energy_mgr.milestones m2 ON m1.project_id = m2.project_id
    WHERE m1.project_id = (SELECT project_id FROM energy_mgr.projects WHERE project_name LIKE '%Roscoe%')
    AND m1.milestone_order < m2.milestone_order
    AND m1.actual_date IS NOT NULL AND m2.actual_date IS NOT NULL
    AND m1.actual_date > m2.actual_date
);" "system" | tr -d '[:space:]')
if [ "${RO_VIOLATIONS:-1}" = "0" ] 2>/dev/null; then
    ROSCOE_OK=true
    MILESTONES_FIXED=$((MILESTONES_FIXED + 1))
fi

HH_VIOLATIONS=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT m1.milestone_name
    FROM energy_mgr.milestones m1
    JOIN energy_mgr.milestones m2 ON m1.project_id = m2.project_id
    WHERE m1.project_id = (SELECT project_id FROM energy_mgr.projects WHERE project_name LIKE '%Horse Hollow%')
    AND m1.milestone_order < m2.milestone_order
    AND m1.actual_date IS NOT NULL AND m2.actual_date IS NOT NULL
    AND m1.actual_date > m2.actual_date
);" "system" | tr -d '[:space:]')
if [ "${HH_VIOLATIONS:-1}" = "0" ] 2>/dev/null; then
    HORSE_HOLLOW_OK=true
    MILESTONES_FIXED=$((MILESTONES_FIXED + 1))
fi

# --- Check PROJECT_HIERARCHY_VW ---
HIER_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ENERGY_MGR' AND view_name = 'PROJECT_HIERARCHY_VW';" "system" | tr -d '[:space:]')
if [ "${HIER_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    HIERARCHY_VW_EXISTS=true
fi

# Check for CONNECT BY in the view definition
CONNECT_BY_USED=false
VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'ENERGY_MGR' AND view_name = 'PROJECT_HIERARCHY_VW';" "system" 2>/dev/null)
if echo "$VW_TEXT" | grep -qiE "CONNECT\s*BY|SYS_CONNECT_BY_PATH" 2>/dev/null; then
    CONNECT_BY_USED=true
fi

# --- Check PORTFOLIO_PIVOT_VW ---
PIVOT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ENERGY_MGR' AND view_name = 'PORTFOLIO_PIVOT_VW';" "system" | tr -d '[:space:]')
if [ "${PIVOT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PIVOT_VW_EXISTS=true
fi

# Check for PIVOT in the view definition
PIVOT_USED=false
PVW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'ENERGY_MGR' AND view_name = 'PORTFOLIO_PIVOT_VW';" "system" 2>/dev/null)
if echo "$PVW_TEXT" | grep -qiE "PIVOT" 2>/dev/null; then
    PIVOT_USED=true
fi

# --- Check DBMS_SCHEDULER job ---
JOB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_scheduler_jobs WHERE owner = 'ENERGY_MGR' AND job_name = 'MILESTONE_STATUS_CHECK';" "system" | tr -d '[:space:]')
if [ "${JOB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SCHEDULER_JOB_EXISTS=true
fi

# --- Check stored procedure ---
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'ENERGY_MGR' AND object_name = 'PROC_CHECK_OVERDUE_MILESTONES';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
fi

# --- Check ALERTS table ---
ALERTS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ENERGY_MGR' AND table_name = 'ALERTS';" "system" | tr -d '[:space:]')
if [ "${ALERTS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ALERTS_TABLE_EXISTS=true
fi

# Check for alerts already populated
ALERT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM energy_mgr.alerts;" "system" | tr -d '[:space:]')
ALERT_COUNT=${ALERT_COUNT:-0}

# --- Check for constraint or trigger preventing sequence violations ---
CONSTRAINT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_triggers WHERE owner = 'ENERGY_MGR' AND table_name = 'MILESTONES' AND status = 'ENABLED';" "system" | tr -d '[:space:]')
CHECK_CONSTRAINT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner = 'ENERGY_MGR' AND table_name = 'MILESTONES' AND constraint_type = 'C' AND search_condition_vc IS NOT NULL;" "system" | tr -d '[:space:]')
if [ "${CONSTRAINT_CHECK:-0}" -gt 0 ] 2>/dev/null || [ "${CHECK_CONSTRAINT_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    CONSTRAINT_EXISTS=true
fi

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# --- Sanitize all numeric values before JSON output ---
MILESTONES_FIXED=$(sanitize_int "$MILESTONES_FIXED" 0)
TOTAL_VIOLATIONS=$(sanitize_int "${TOTAL_VIOLATIONS:-99}" 99)
ALERT_COUNT=$(sanitize_int "${ALERT_COUNT:-0}" 0)

# --- Write result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "milestones_fixed_count": $MILESTONES_FIXED,
    "total_remaining_violations": $TOTAL_VIOLATIONS,
    "shepherds_flat_fixed": $SHEPHERDS_FLAT_OK,
    "alta_wind_fixed": $ALTA_WIND_OK,
    "roscoe_fixed": $ROSCOE_OK,
    "horse_hollow_fixed": $HORSE_HOLLOW_OK,
    "hierarchy_vw_exists": $HIERARCHY_VW_EXISTS,
    "connect_by_used": $CONNECT_BY_USED,
    "pivot_vw_exists": $PIVOT_VW_EXISTS,
    "pivot_used": $PIVOT_USED,
    "scheduler_job_exists": $SCHEDULER_JOB_EXISTS,
    "overdue_proc_exists": $PROC_EXISTS,
    "alerts_table_exists": $ALERTS_TABLE_EXISTS,
    "alert_count": $ALERT_COUNT,
    "constraint_exists": $CONSTRAINT_EXISTS,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/energy_portfolio_result.json 2>/dev/null || sudo rm -f /tmp/energy_portfolio_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/energy_portfolio_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/energy_portfolio_result.json
chmod 666 /tmp/energy_portfolio_result.json 2>/dev/null || sudo chmod 666 /tmp/energy_portfolio_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/energy_portfolio_result.json"
cat /tmp/energy_portfolio_result.json
echo "=== Export complete ==="
