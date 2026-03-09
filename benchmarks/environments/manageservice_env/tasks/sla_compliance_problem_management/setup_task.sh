#!/bin/bash
# Setup for "sla_compliance_problem_management" task
# IT Operations Manager remediation: triage high-priority tickets + create Problem record

echo "=== Setting up SLA Compliance Problem Management task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure export script is executable (Lesson 120)
chmod +x /workspace/tasks/sla_compliance_problem_management/export_result.sh 2>/dev/null || true

ensure_sdp_running

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp

# --- Verify target tickets exist ---
TICKET_CHECK=$(sdp_db_exec "SELECT COUNT(*) FROM workorder WHERE workorderid IN (1001,1003,1004);" 2>/dev/null | tr -d '[:space:]')
if [ "${TICKET_CHECK:-0}" != "3" ]; then
    log "WARNING: Expected 3 target tickets (1001,1003,1004), found ${TICKET_CHECK:-0}"
fi

# --- Record baseline state ---
BASELINE_FILE="/tmp/sla_compliance_initial.json"

STATUS_1001=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1001;" 2>/dev/null | tr -d '[:space:]')
STATUS_1003=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1003;" 2>/dev/null | tr -d '[:space:]')
STATUS_1004=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')
OWNER_1001=$(sdp_db_exec "SELECT ownerId FROM workorderstates WHERE workorderid=1001;" 2>/dev/null | tr -d '[:space:]')
OWNER_1003=$(sdp_db_exec "SELECT ownerId FROM workorderstates WHERE workorderid=1003;" 2>/dev/null | tr -d '[:space:]')
OWNER_1004=$(sdp_db_exec "SELECT ownerId FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')

cat > "$BASELINE_FILE" << EOF
{
  "initial_status_1001": ${STATUS_1001:-2},
  "initial_status_1003": ${STATUS_1003:-2},
  "initial_status_1004": ${STATUS_1004:-2},
  "initial_owner_1001": ${OWNER_1001:-0},
  "initial_owner_1003": ${OWNER_1003:-0},
  "initial_owner_1004": ${OWNER_1004:-0},
  "task_start_time": $(date +%s%3N)
}
EOF

log "Baseline recorded: statuses=$STATUS_1001/$STATUS_1003/$STATUS_1004 owners=$OWNER_1001/$OWNER_1003/$OWNER_1004"

# Open Firefox on the Requests list (agent must discover and triage the tickets)
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
sleep 5

take_screenshot /tmp/sla_compliance_start.png

echo "=== SLA Compliance Problem Management task ready ==="
echo "Three Open High-priority requests await triage: 1001 (keyboard), 1003 (printer), 1004 (VPN)."
echo "Log in with administrator / administrator"
