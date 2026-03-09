#!/bin/bash
echo "=== Setting up milestone_replanning task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Redmine is up
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Record baseline state for both target issues
API_KEY=$(redmine_admin_api_key)

LOG_AGG_ID=$(redmine_issue_id_by_subject "centralized log aggregation")
K8S_ID=$(redmine_issue_id_by_subject "Kubernetes cluster for production")

if [ -n "$LOG_AGG_ID" ] && [ "$LOG_AGG_ID" != "null" ]; then
  LOG_AGG_BASELINE=$(curl -s \
    "http://localhost:3000/issues/${LOG_AGG_ID}.json?key=${API_KEY}" \
    | jq '{version: (.issue.fixed_version.name // "none"), priority: .issue.priority.name}' \
    2>/dev/null || echo '{"version":"unknown","priority":"unknown"}')
  echo "$LOG_AGG_BASELINE" > /tmp/task_baseline_log_agg_milestone.json
  log "Log agg baseline: $LOG_AGG_BASELINE"
fi

if [ -n "$K8S_ID" ] && [ "$K8S_ID" != "null" ]; then
  K8S_BASELINE=$(curl -s \
    "http://localhost:3000/issues/${K8S_ID}.json?key=${API_KEY}&include=journals" \
    | jq '{priority: .issue.priority.name, comment_count: ([.issue.journals[] | select(.notes != "")] | length)}' \
    2>/dev/null || echo '{"priority":"unknown","comment_count":0}')
  echo "$K8S_BASELINE" > /tmp/task_baseline_k8s.json
  log "K8s baseline: $K8S_BASELINE"
fi

# Record infra-devops issue count baseline
BASELINE_ISSUE_COUNT=$(curl -s \
  "http://localhost:3000/issues.json?project_id=infra-devops&key=${API_KEY}&status_id=*&limit=1" \
  | jq '.total_count // 0' 2>/dev/null || echo "0")
echo "$BASELINE_ISSUE_COUNT" > /tmp/task_baseline_infra_count_milestone
log "Infra-devops baseline issue count: $BASELINE_ISSUE_COUNT"

# Open Firefox at infra-devops project
TARGET_URL="${REDMINE_BASE_URL}/projects/infra-devops/issues"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png
log "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
