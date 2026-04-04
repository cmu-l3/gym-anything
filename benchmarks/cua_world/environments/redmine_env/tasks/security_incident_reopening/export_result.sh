#!/bin/bash
echo "=== Exporting security_incident_reopening result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/security_incident_reopening_result.json"
API_KEY=$(redmine_admin_api_key)
BASE_URL="http://localhost:3000"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo '{"error":"no_api_key"}' > "$RESULT_FILE"
  exit 0
fi

# Get SSL cert issue ID from seed result
SSL_CERT_ID=$(redmine_issue_id_by_subject "SSL certificate for api.devlabs.io")
echo "SSL cert issue ID: $SSL_CERT_ID"

if [ -z "$SSL_CERT_ID" ] || [ "$SSL_CERT_ID" = "null" ]; then
  echo '{"error":"ssl_cert_issue_not_found"}' > "$RESULT_FILE"
  exit 0
fi

# Fetch SSL cert issue with journals
curl -sf "${BASE_URL}/issues/${SSL_CERT_ID}.json?key=${API_KEY}&include=journals" \
  > /tmp/_sir_ssl.json 2>/dev/null || echo '{"issue":{}}' > /tmp/_sir_ssl.json

# Fetch time entries for SSL cert issue
curl -sf "${BASE_URL}/time_entries.json?issue_id=${SSL_CERT_ID}&key=${API_KEY}&limit=100" \
  > /tmp/_sir_time.json 2>/dev/null || echo '{"time_entries":[]}' > /tmp/_sir_time.json

# Search for new certbot monitoring issue (created during task)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
curl -sf "${BASE_URL}/issues.json?project_id=infra-devops&key=${API_KEY}&status_id=*&limit=100" \
  > /tmp/_sir_infra_issues.json 2>/dev/null || echo '{"issues":[]}' > /tmp/_sir_infra_issues.json

# Extract SSL cert fields
SSL_STATUS=$(jq -r '.issue.status.name // "unknown"' /tmp/_sir_ssl.json)
SSL_PRIORITY=$(jq -r '.issue.priority.name // "unknown"' /tmp/_sir_ssl.json)
SSL_COMMENTS=$(jq -c '[.issue.journals[] | select(.notes != "") | .notes]' /tmp/_sir_ssl.json 2>/dev/null || echo '[]')
SSL_COMMENT_COUNT=$(jq '[.issue.journals[] | select(.notes != "")] | length' /tmp/_sir_ssl.json 2>/dev/null || echo "0")

# Extract time entries for SSL cert
SSL_TIME_ENTRIES=$(jq -c '[.time_entries[] | {hours: .hours, activity: .activity.name, comments: .comments}]' \
  /tmp/_sir_time.json 2>/dev/null || echo '[]')
SSL_TOTAL_HOURS=$(jq '[.time_entries[].hours] | add // 0' /tmp/_sir_time.json 2>/dev/null || echo "0")

# Find certbot monitoring issue (by subject fragment, created after task start would be ideal
# but we check by subject since creation time is unreliable in Redmine's API without filtering)
CERTBOT_ISSUE=$(jq -c '
  .issues[]
  | select(
      (.subject | ascii_downcase | contains("certbot")) or
      (.subject | ascii_downcase | contains("renewal verification")) or
      (.subject | ascii_downcase | contains("cron"))
    )
  | {id: .id, subject: .subject, status: .status.name, priority: .priority.name,
     assigned_to: (.assigned_to.name // "none"), tracker: .tracker.name,
     fixed_version: (.fixed_version.name // "none"),
     estimated_hours: (.estimated_hours // 0)}
' /tmp/_sir_infra_issues.json 2>/dev/null | head -1)

if [ -z "$CERTBOT_ISSUE" ]; then
  CERTBOT_ISSUE='null'
fi

BASELINE_SSL_COMMENTS=$(cat /tmp/task_baseline_ssl_comments 2>/dev/null || echo "0")

# Build result JSON
jq -n \
  --argjson ssl_id "$SSL_CERT_ID" \
  --arg ssl_status "$SSL_STATUS" \
  --arg ssl_priority "$SSL_PRIORITY" \
  --argjson ssl_comments "$SSL_COMMENTS" \
  --argjson ssl_comment_count "$SSL_COMMENT_COUNT" \
  --argjson ssl_time_entries "$SSL_TIME_ENTRIES" \
  --argjson ssl_total_hours "$SSL_TOTAL_HOURS" \
  --argjson certbot_issue "$CERTBOT_ISSUE" \
  --argjson task_start "$TASK_START" \
  --argjson baseline_comments "$BASELINE_SSL_COMMENTS" \
  '{
    task_start_timestamp: $task_start,
    ssl_cert_issue: {
      id: $ssl_id,
      status: $ssl_status,
      priority: $ssl_priority,
      comments: $ssl_comments,
      comment_count: $ssl_comment_count,
      baseline_comment_count: $baseline_comments,
      time_entries: $ssl_time_entries,
      total_hours_logged: $ssl_total_hours
    },
    certbot_monitoring_issue: $certbot_issue
  }' > "$RESULT_FILE"

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="
