#!/bin/bash
# Setup for "technician_group_routing_configuration" task
# IT Service Desk Manager: create groups, technicians, route tickets

echo "=== Setting up Technician Group Routing Configuration task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure export script is executable (Lesson 120)
chmod +x /workspace/tasks/technician_group_routing_configuration/export_result.sh 2>/dev/null || true

ensure_sdp_running

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp

# --- Verify target tickets exist ---
TICKET_CHECK=$(sdp_db_exec "SELECT COUNT(*) FROM workorder WHERE workorderid IN (1001,1004);" 2>/dev/null | tr -d '[:space:]')
if [ "${TICKET_CHECK:-0}" != "2" ]; then
    log "WARNING: Expected 2 target tickets (1001,1004), found ${TICKET_CHECK:-0}"
fi

# --- Record baseline state ---
BASELINE_FILE="/tmp/technician_group_routing_initial.json"

# Count existing technician groups (try multiple table names)
GROUP_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM supportgroup;" 2>/dev/null | tr -d '[:space:]')
GROUP_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM techniciangroup;" 2>/dev/null | tr -d '[:space:]')

# Count existing technicians (sduser with typeid=1 or similar for technicians)
TECH_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM sduser WHERE status='ACTIVE';" 2>/dev/null | tr -d '[:space:]')

# Check if Maya Patel / Carlos Rivera already exist
MAYA_EXISTS=$(sdp_db_exec "SELECT COUNT(*) FROM sduser WHERE LOWER(firstname)='maya' AND LOWER(lastname)='patel';" 2>/dev/null | tr -d '[:space:]')
CARLOS_EXISTS=$(sdp_db_exec "SELECT COUNT(*) FROM sduser WHERE LOWER(firstname)='carlos' AND LOWER(lastname)='rivera';" 2>/dev/null | tr -d '[:space:]')

# Check existing group assignment for tickets 1001 and 1004
GROUP_1001=$(sdp_db_exec "SELECT groupid FROM workorderstates WHERE workorderid=1001;" 2>/dev/null | tr -d '[:space:]')
GROUP_1004=$(sdp_db_exec "SELECT groupid FROM workorderstates WHERE workorderid=1004;" 2>/dev/null | tr -d '[:space:]')

cat > "$BASELINE_FILE" << EOF
{
  "initial_group_count": ${GROUP_COUNT:-0},
  "initial_group_count_alt": ${GROUP_COUNT_ALT:-0},
  "initial_tech_count": ${TECH_COUNT:-0},
  "maya_patel_existed": ${MAYA_EXISTS:-0},
  "carlos_rivera_existed": ${CARLOS_EXISTS:-0},
  "initial_group_1001": ${GROUP_1001:-0},
  "initial_group_1004": ${GROUP_1004:-0},
  "task_start_time": $(date +%s%3N)
}
EOF

log "Baseline recorded: groups=$GROUP_COUNT techs=$TECH_COUNT maya_existed=$MAYA_EXISTS carlos_existed=$CARLOS_EXISTS"

# Open Firefox on the Admin panel so the agent can navigate to Groups/Technicians
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
sleep 5

take_screenshot /tmp/technician_group_routing_start.png

echo "=== Technician Group Routing Configuration task ready ==="
echo "The service desk has no specialized technician groups. Create groups, add technicians, and route tickets."
echo "Log in with administrator / administrator"
