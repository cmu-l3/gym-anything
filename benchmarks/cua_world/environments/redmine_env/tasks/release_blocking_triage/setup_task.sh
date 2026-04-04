#!/bin/bash
echo "=== Setting up release_blocking_triage task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Redmine is up
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Record baseline state for payment gateway issue (to detect newly added comments)
API_KEY=$(redmine_admin_api_key)
PAYMENT_GW_ID=$(redmine_issue_id_by_subject "Payment gateway timeout")
if [ -n "$PAYMENT_GW_ID" ] && [ "$PAYMENT_GW_ID" != "null" ]; then
  BASELINE_COMMENT_COUNT=$(curl -s \
    "http://localhost:3000/issues/${PAYMENT_GW_ID}.json?key=${API_KEY}&include=journals" \
    | jq '[.issue.journals[] | select(.notes != "")] | length' 2>/dev/null || echo "0")
  echo "$BASELINE_COMMENT_COUNT" > /tmp/task_baseline_payment_gw_comments
  log "Payment gateway issue #${PAYMENT_GW_ID} baseline comment count: $BASELINE_COMMENT_COUNT"
else
  echo "0" > /tmp/task_baseline_payment_gw_comments
fi

# Open Firefox at the phoenix-ecommerce issues list filtered to v1.0 Launch
TARGET_URL="${REDMINE_BASE_URL}/projects/phoenix-ecommerce/issues?fixed_version_id=&set_filter=1&f[]=fixed_version_id"

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
