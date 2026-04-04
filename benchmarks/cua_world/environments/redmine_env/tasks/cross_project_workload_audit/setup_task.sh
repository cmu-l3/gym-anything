#!/bin/bash
echo "=== Setting up cross_project_workload_audit task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Redmine is up
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Record baseline state for the log aggregation issue (the expected target)
API_KEY=$(redmine_admin_api_key)
LOG_AGG_ID=$(redmine_issue_id_by_subject "centralized log aggregation")
if [ -n "$LOG_AGG_ID" ] && [ "$LOG_AGG_ID" != "null" ]; then
  BASELINE_DATA=$(curl -s \
    "http://localhost:3000/issues/${LOG_AGG_ID}.json?key=${API_KEY}&include=journals" \
    | jq '{assignee: (.issue.assigned_to.name // "none"), estimated_hours: (.issue.estimated_hours // 0), comment_count: ([.issue.journals[] | select(.notes != "")] | length)}' \
    2>/dev/null || echo '{"assignee":"unknown","estimated_hours":0,"comment_count":0}')
  echo "$BASELINE_DATA" > /tmp/task_baseline_log_agg.json
  log "Log aggregation issue #${LOG_AGG_ID} baseline: $BASELINE_DATA"
fi

# Open Firefox at the Issues overview (all projects) to aid workload analysis
TARGET_URL="${REDMINE_BASE_URL}/issues?set_filter=1&f[]=status_id&op[status_id]=o&f[]=assigned_to_id&op[assigned_to_id]==&v[assigned_to_id][]=me"

log "Opening Firefox at: ${REDMINE_BASE_URL}"
if ! ensure_redmine_logged_in "${REDMINE_BASE_URL}/issues?set_filter=1&f[]=status_id&op[status_id]=o"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png
log "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
