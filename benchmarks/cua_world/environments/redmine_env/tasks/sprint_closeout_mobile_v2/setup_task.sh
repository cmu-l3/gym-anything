#!/bin/bash
echo "=== Setting up sprint_closeout_mobile_v2 task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Redmine is up
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Record baseline states
API_KEY=$(redmine_admin_api_key)

DARK_MODE_ID=$(redmine_issue_id_by_subject "Dark mode: tab bar icons inverted")
OFFLINE_SYNC_ID=$(redmine_issue_id_by_subject "Offline mode: local changes lost")
PUSH_NOTIF_ID=$(redmine_issue_id_by_subject "Push notifications not delivered")

for ISSUE_TUPLE in "${DARK_MODE_ID}:dark_mode" "${OFFLINE_SYNC_ID}:offline_sync" "${PUSH_NOTIF_ID}:push_notif"; do
  ISSUE_ID="${ISSUE_TUPLE%%:*}"
  ISSUE_KEY="${ISSUE_TUPLE##*:}"
  if [ -n "$ISSUE_ID" ] && [ "$ISSUE_ID" != "null" ]; then
    BASELINE=$(curl -s \
      "http://localhost:3000/issues/${ISSUE_ID}.json?key=${API_KEY}&include=journals" \
      | jq '{status: .issue.status.name, version: (.issue.fixed_version.name // "none"), comment_count: ([.issue.journals[] | select(.notes != "")] | length)}' \
      2>/dev/null || echo '{}')
    echo "$BASELINE" > "/tmp/task_baseline_${ISSUE_KEY}.json"
    log "${ISSUE_KEY} issue #${ISSUE_ID} baseline: $BASELINE"
  fi
done

# Record mobile-app-v2 issue count baseline
BASELINE_MOBILE_COUNT=$(curl -s \
  "http://localhost:3000/issues.json?project_id=mobile-app-v2&key=${API_KEY}&status_id=*&limit=1" \
  | jq '.total_count // 0' 2>/dev/null || echo "0")
echo "$BASELINE_MOBILE_COUNT" > /tmp/task_baseline_mobile_count
log "Mobile app v2 baseline issue count: $BASELINE_MOBILE_COUNT"

# Open Firefox at mobile-app-v2 project issues filtered to v2.0 Release
TARGET_URL="${REDMINE_BASE_URL}/projects/mobile-app-v2/issues"
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
