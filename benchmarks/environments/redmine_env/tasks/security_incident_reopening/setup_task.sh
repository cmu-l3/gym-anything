#!/bin/bash
echo "=== Setting up security_incident_reopening task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Redmine is up
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Record baseline: number of issues in infra-devops (to detect newly created issues)
API_KEY=$(redmine_admin_api_key)
BASELINE_ISSUE_COUNT=$(curl -s \
  "http://localhost:3000/issues.json?project_id=infra-devops&key=${API_KEY}&status_id=*&limit=1" \
  | jq '.total_count // 0' 2>/dev/null || echo "0")
echo "$BASELINE_ISSUE_COUNT" > /tmp/task_baseline_infra_issue_count
log "Infra-devops baseline issue count: $BASELINE_ISSUE_COUNT"

# Record baseline comment count on SSL cert issue
SSL_CERT_ID=$(redmine_issue_id_by_subject "SSL certificate for api.devlabs.io")
if [ -n "$SSL_CERT_ID" ] && [ "$SSL_CERT_ID" != "null" ]; then
  BASELINE_SSL_COMMENTS=$(curl -s \
    "http://localhost:3000/issues/${SSL_CERT_ID}.json?key=${API_KEY}&include=journals" \
    | jq '[.issue.journals[] | select(.notes != "")] | length' 2>/dev/null || echo "0")
  echo "$BASELINE_SSL_COMMENTS" > /tmp/task_baseline_ssl_comments
  log "SSL cert issue #${SSL_CERT_ID} baseline comment count: $BASELINE_SSL_COMMENTS"
else
  echo "0" > /tmp/task_baseline_ssl_comments
fi

# Open Firefox at the infra-devops project issues page
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
