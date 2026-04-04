#!/bin/bash
echo "=== Exporting sprint_closeout_mobile_v2 result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/sprint_closeout_mobile_v2_result.json"
API_KEY=$(redmine_admin_api_key)
BASE_URL="http://localhost:3000"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo '{"error":"no_api_key"}' > "$RESULT_FILE"
  exit 0
fi

# Get issue IDs from seed result
DARK_MODE_ID=$(redmine_issue_id_by_subject "Dark mode: tab bar icons inverted")
OFFLINE_SYNC_ID=$(redmine_issue_id_by_subject "Offline mode: local changes lost")
PUSH_NOTIF_ID=$(redmine_issue_id_by_subject "Push notifications not delivered")

echo "Dark mode issue ID: $DARK_MODE_ID"
echo "Offline sync issue ID: $OFFLINE_SYNC_ID"
echo "Push notif issue ID: $PUSH_NOTIF_ID"

# Fetch all three issues
for ISSUE_ID_VAR in DARK_MODE_ID OFFLINE_SYNC_ID PUSH_NOTIF_ID; do
  ISSUE_ID="${!ISSUE_ID_VAR}"
  SUFFIX="${ISSUE_ID_VAR,,}"
  if [ -n "$ISSUE_ID" ] && [ "$ISSUE_ID" != "null" ]; then
    curl -sf "${BASE_URL}/issues/${ISSUE_ID}.json?key=${API_KEY}&include=journals" \
      > "/tmp/_scm_${SUFFIX}.json" 2>/dev/null || echo '{"issue":{}}' > "/tmp/_scm_${SUFFIX}.json"
  else
    echo '{"issue":{}}' > "/tmp/_scm_${SUFFIX}.json"
  fi
done

# Fetch time entries for push notif issue
PUSH_NOTIF_ENTRIES='{"time_entries":[]}'
if [ -n "$PUSH_NOTIF_ID" ] && [ "$PUSH_NOTIF_ID" != "null" ]; then
  curl -sf "${BASE_URL}/time_entries.json?issue_id=${PUSH_NOTIF_ID}&key=${API_KEY}&limit=100" \
    > /tmp/_scm_push_time.json 2>/dev/null || echo '{"time_entries":[]}' > /tmp/_scm_push_time.json
else
  echo '{"time_entries":[]}' > /tmp/_scm_push_time.json
fi

# Search for closeout summary issue in mobile-app-v2
curl -sf "${BASE_URL}/issues.json?project_id=mobile-app-v2&key=${API_KEY}&status_id=*&limit=100" \
  > /tmp/_scm_mobile_issues.json 2>/dev/null || echo '{"issues":[]}' > /tmp/_scm_mobile_issues.json

# Extract fields
DARK_MODE_STATUS=$(jq -r '.issue.status.name // "unknown"' /tmp/_scm_dark_mode_id.json)

OFFLINE_STATUS=$(jq -r '.issue.status.name // "unknown"' /tmp/_scm_offline_sync_id.json)
OFFLINE_VERSION=$(jq -r '.issue.fixed_version.name // "none"' /tmp/_scm_offline_sync_id.json)
OFFLINE_COMMENTS=$(jq -c '[.issue.journals[] | select(.notes != "") | .notes]' \
  /tmp/_scm_offline_sync_id.json 2>/dev/null || echo '[]')

PUSH_STATUS=$(jq -r '.issue.status.name // "unknown"' /tmp/_scm_push_notif_id.json)
PUSH_COMMENTS=$(jq -c '[.issue.journals[] | select(.notes != "") | .notes]' \
  /tmp/_scm_push_notif_id.json 2>/dev/null || echo '[]')

PUSH_TIME_ENTRIES=$(jq -c '[.time_entries[] | {hours: .hours, activity: .activity.name, user: .user.name, comments: .comments}]' \
  /tmp/_scm_push_time.json 2>/dev/null || echo '[]')
PUSH_TESTING_HOURS=$(jq '[.time_entries[] | select(.activity.name | ascii_downcase | contains("test")) | .hours] | add // 0' \
  /tmp/_scm_push_time.json 2>/dev/null || echo "0")
PUSH_TOTAL_HOURS=$(jq '[.time_entries[].hours] | add // 0' /tmp/_scm_push_time.json 2>/dev/null || echo "0")

# Find closeout summary issue
CLOSEOUT_ISSUE=$(jq -c '
  .issues[]
  | select(
      (.subject | ascii_downcase | contains("closeout")) or
      (.subject | ascii_downcase | contains("sprint closeout")) or
      (.subject | ascii_downcase | contains("v2.0 release sprint"))
    )
  | {id: .id, subject: .subject, status: .status.name, priority: .priority.name,
     assigned_to: (.assigned_to.name // "none"),
     fixed_version: (.fixed_version.name // "none"),
     tracker: .tracker.name}
' /tmp/_scm_mobile_issues.json 2>/dev/null | head -1)

if [ -z "$CLOSEOUT_ISSUE" ]; then
  CLOSEOUT_ISSUE='null'
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
BASELINE_DARK=$(cat /tmp/task_baseline_dark_mode.json 2>/dev/null || echo '{}')
BASELINE_OFFLINE=$(cat /tmp/task_baseline_offline_sync.json 2>/dev/null || echo '{}')
BASELINE_PUSH=$(cat /tmp/task_baseline_push_notif.json 2>/dev/null || echo '{}')

# Build result JSON
jq -n \
  --argjson dark_mode_id "${DARK_MODE_ID:-0}" \
  --arg dark_mode_status "$DARK_MODE_STATUS" \
  --argjson offline_id "${OFFLINE_SYNC_ID:-0}" \
  --arg offline_status "$OFFLINE_STATUS" \
  --arg offline_version "$OFFLINE_VERSION" \
  --argjson offline_comments "$OFFLINE_COMMENTS" \
  --argjson push_id "${PUSH_NOTIF_ID:-0}" \
  --arg push_status "$PUSH_STATUS" \
  --argjson push_comments "$PUSH_COMMENTS" \
  --argjson push_time_entries "$PUSH_TIME_ENTRIES" \
  --argjson push_testing_hours "$PUSH_TESTING_HOURS" \
  --argjson push_total_hours "$PUSH_TOTAL_HOURS" \
  --argjson closeout_issue "$CLOSEOUT_ISSUE" \
  --argjson task_start "$TASK_START" \
  --argjson baseline_dark "$BASELINE_DARK" \
  --argjson baseline_offline "$BASELINE_OFFLINE" \
  --argjson baseline_push "$BASELINE_PUSH" \
  '{
    task_start_timestamp: $task_start,
    dark_mode_issue: {
      id: $dark_mode_id,
      status: $dark_mode_status,
      baseline: $baseline_dark
    },
    offline_sync_issue: {
      id: $offline_id,
      status: $offline_status,
      current_version: $offline_version,
      comments: $offline_comments,
      baseline: $baseline_offline
    },
    push_notif_issue: {
      id: $push_id,
      status: $push_status,
      comments: $push_comments,
      time_entries: $push_time_entries,
      testing_hours: $push_testing_hours,
      total_hours: $push_total_hours,
      baseline: $baseline_push
    },
    closeout_issue: $closeout_issue
  }' > "$RESULT_FILE"

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="
