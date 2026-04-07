#!/bin/bash
# Setup for "problem_to_fix_full_lifecycle" task
# Senior ITSM Admin: full ITIL lifecycle from problem creation through resolution
# Spans Problems, Requests, Changes, and Solutions modules

echo "=== Setting up Problem-to-Fix Full Lifecycle task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure export script is executable
chmod +x /workspace/tasks/problem_to_fix_full_lifecycle/export_result.sh 2>/dev/null || true

ensure_sdp_running

# --- Delete stale outputs from any prior run ---
rm -f /tmp/problem_to_fix_full_lifecycle_result.json
rm -f /tmp/problem_to_fix_lifecycle_sql_raw.json
rm -f /tmp/problem_to_fix_full_lifecycle_start.png
rm -f /tmp/problem_to_fix_full_lifecycle_final.png

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp

# --- Verify target tickets exist ---
TICKET_CHECK=$(sdp_db_exec "SELECT COUNT(*) FROM workorder WHERE workorderid IN (1001,1003,1004);" 2>/dev/null | tr -d '[:space:]')
if [ "${TICKET_CHECK:-0}" != "3" ]; then
    log "WARNING: Expected 3 target tickets (1001,1003,1004), found ${TICKET_CHECK:-0}"
fi

# --- Record baseline state ---
BASELINE_FILE="/tmp/problem_to_fix_full_lifecycle_initial.json"

# Problem counts (try multiple table names — SDP version dependent)
PROBLEM_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM problem;" 2>/dev/null | tr -d '[:space:]')
PROBLEM_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM problemdetails;" 2>/dev/null | tr -d '[:space:]')

# Change counts
CHANGE_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM changedetails;" 2>/dev/null | tr -d '[:space:]')
CHANGE_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM changemanagement;" 2>/dev/null | tr -d '[:space:]')

# KB article counts
KB_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM solution;" 2>/dev/null | tr -d '[:space:]')
KB_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM knowledgebase;" 2>/dev/null | tr -d '[:space:]')

# Ticket statuses
STATUS_1001=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1001;" 2>/dev/null | tr -d '[:space:]')
STATUS_1003=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1003;" 2>/dev/null | tr -d '[:space:]')
STATUS_1004=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')

cat > "$BASELINE_FILE" << EOF
{
  "initial_problem_count": ${PROBLEM_COUNT:-0},
  "initial_problem_count_alt": ${PROBLEM_COUNT_ALT:-0},
  "initial_change_count": ${CHANGE_COUNT:-0},
  "initial_change_count_alt": ${CHANGE_COUNT_ALT:-0},
  "initial_kb_count": ${KB_COUNT:-0},
  "initial_kb_count_alt": ${KB_COUNT_ALT:-0},
  "initial_status_1001": ${STATUS_1001:-2},
  "initial_status_1003": ${STATUS_1003:-2},
  "initial_status_1004": ${STATUS_1004:-2},
  "task_start_time": $(date +%s%3N)
}
EOF

log "Baseline: problems=${PROBLEM_COUNT:-0} changes=${CHANGE_COUNT:-0} kb=${KB_COUNT:-0}"
log "Ticket statuses: 1001=${STATUS_1001:-?} 1003=${STATUS_1003:-?} 1004=${STATUS_1004:-?}"

# Open Firefox on the Requests list — agent sees the symptom tickets first
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
sleep 5

take_screenshot /tmp/problem_to_fix_full_lifecycle_start.png

echo "=== Problem-to-Fix Full Lifecycle task ready ==="
echo "Three open tickets trace to a faulty network switch. Execute the full ITIL lifecycle."
echo "Log in with administrator / administrator"
