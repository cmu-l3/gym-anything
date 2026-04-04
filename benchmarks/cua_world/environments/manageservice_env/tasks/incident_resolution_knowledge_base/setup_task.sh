#!/bin/bash
# Setup for "incident_resolution_knowledge_base" task
# Senior IT Specialist: resolve tickets, close, create KB article

echo "=== Setting up Incident Resolution Knowledge Base task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure export script is executable (Lesson 120)
chmod +x /workspace/tasks/incident_resolution_knowledge_base/export_result.sh 2>/dev/null || true

ensure_sdp_running

# --- Record task start timestamp ---
date +%s > /tmp/task_start_timestamp

# --- Verify target tickets exist ---
TICKET_CHECK=$(sdp_db_exec "SELECT COUNT(*) FROM workorder WHERE workorderid IN (1002,1005);" 2>/dev/null | tr -d '[:space:]')
if [ "${TICKET_CHECK:-0}" != "2" ]; then
    log "WARNING: Expected 2 target tickets (1002,1005), found ${TICKET_CHECK:-0}"
fi

# --- Record baseline state ---
BASELINE_FILE="/tmp/incident_resolution_knowledge_base_initial.json"

# Status of target tickets
STATUS_1002=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1002;" 2>/dev/null | tr -d '[:space:]')
STATUS_1005=$(sdp_db_exec "SELECT statusid FROM workorderstates WHERE workorderid=1005;" 2>/dev/null | tr -d '[:space:]')

# Count existing KB articles
KB_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM solution;" 2>/dev/null | tr -d '[:space:]')
KB_COUNT_ALT=$(sdp_db_exec "SELECT COUNT(*) FROM knowledgebase;" 2>/dev/null | tr -d '[:space:]')

cat > "$BASELINE_FILE" << EOF
{
  "initial_status_1002": ${STATUS_1002:-2},
  "initial_status_1005": ${STATUS_1005:-2},
  "initial_kb_count": ${KB_COUNT:-0},
  "initial_kb_count_alt": ${KB_COUNT_ALT:-0},
  "task_start_time": $(date +%s%3N)
}
EOF

log "Baseline: status_1002=$STATUS_1002 status_1005=$STATUS_1005 kb_count=$KB_COUNT"

# Open Firefox on requests list
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
sleep 5

take_screenshot /tmp/incident_resolution_knowledge_base_start.png

echo "=== Incident Resolution Knowledge Base task ready ==="
echo "Two tickets need resolution: 1002 (email) and 1005 (Adobe Acrobat). Then create a KB article."
echo "Log in with administrator / administrator"
