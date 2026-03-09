#!/bin/bash
# Setup for "change_request_full_lifecycle" task
# Change Manager: create full RFC with tasks, link incidents, submit for CAB review

echo "=== Setting up Change Request Full Lifecycle task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure export script is executable (Lesson 120)
chmod +x /workspace/tasks/change_request_full_lifecycle/export_result.sh 2>/dev/null || true

ensure_sdp_running

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp

# --- Record baseline state ---
BASELINE_FILE="/tmp/change_request_full_lifecycle_initial.json"

# Try multiple table names for changes
CHANGE_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM changemanagement;" 2>/dev/null | tr -d '[:space:]')
CHANGE_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM changedetails;" 2>/dev/null | tr -d '[:space:]')
CHANGE_COUNT_ALT2=$(sdp_db_exec "SELECT COUNT(*) FROM globalchange;" 2>/dev/null | tr -d '[:space:]')

# Verify ticket 1004 exists (the VPN ticket that will be linked)
VPN_TICKET_STATUS=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')

cat > "$BASELINE_FILE" << EOF
{
  "initial_change_count": ${CHANGE_COUNT:-0},
  "initial_change_count_alt": ${CHANGE_COUNT_ALT:-0},
  "initial_change_count_alt2": ${CHANGE_COUNT_ALT2:-0},
  "vpn_ticket_1004_status": ${VPN_TICKET_STATUS:-2},
  "task_start_time": $(date +%s%3N)
}
EOF

log "Baseline recorded: changes=$CHANGE_COUNT vpn_ticket_status=$VPN_TICKET_STATUS"

# Open Firefox on the Changes module
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
sleep 5

take_screenshot /tmp/change_request_full_lifecycle_start.png

echo "=== Change Request Full Lifecycle task ready ==="
echo "Create a complete Change Request for the campus network switch replacement."
echo "Log in with administrator / administrator"
