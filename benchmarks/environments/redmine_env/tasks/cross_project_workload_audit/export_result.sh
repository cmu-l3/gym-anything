#!/bin/bash
echo "=== Exporting cross_project_workload_audit result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/cross_project_workload_audit_result.json"
API_KEY=$(redmine_admin_api_key)
BASE_URL="http://localhost:3000"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo '{"error":"no_api_key"}' > "$RESULT_FILE"
  exit 0
fi

# Get log aggregation issue ID (the expected reassignment target)
LOG_AGG_ID=$(redmine_issue_id_by_subject "centralized log aggregation")
echo "Log aggregation issue ID: $LOG_AGG_ID"

if [ -z "$LOG_AGG_ID" ] || [ "$LOG_AGG_ID" = "null" ]; then
  echo '{"error":"log_aggregation_issue_not_found"}' > "$RESULT_FILE"
  exit 0
fi

# Fetch log aggregation issue with journals
curl -sf "${BASE_URL}/issues/${LOG_AGG_ID}.json?key=${API_KEY}&include=journals" \
  > /tmp/_cpwa_log_agg.json 2>/dev/null || echo '{"issue":{}}' > /tmp/_cpwa_log_agg.json

# Fetch time entries for log aggregation issue
curl -sf "${BASE_URL}/time_entries.json?issue_id=${LOG_AGG_ID}&key=${API_KEY}&limit=100" \
  > /tmp/_cpwa_time.json 2>/dev/null || echo '{"time_entries":[]}' > /tmp/_cpwa_time.json

# Extract fields from log aggregation issue
LOG_AGG_STATUS=$(jq -r '.issue.status.name // "unknown"' /tmp/_cpwa_log_agg.json)
LOG_AGG_ASSIGNEE=$(jq -r '.issue.assigned_to.name // "none"' /tmp/_cpwa_log_agg.json)
LOG_AGG_ASSIGNEE_ID=$(jq -r '.issue.assigned_to.id // 0' /tmp/_cpwa_log_agg.json)
LOG_AGG_EST_HOURS=$(jq -r '.issue.estimated_hours // 0' /tmp/_cpwa_log_agg.json)
LOG_AGG_COMMENTS=$(jq -c '[.issue.journals[] | select(.notes != "") | .notes]' \
  /tmp/_cpwa_log_agg.json 2>/dev/null || echo '[]')

# Baseline state
BASELINE_ASSIGNEE=$(jq -r '.assignee // "unknown"' /tmp/task_baseline_log_agg.json 2>/dev/null || echo "unknown")
BASELINE_EST_HOURS=$(jq -r '.estimated_hours // 0' /tmp/task_baseline_log_agg.json 2>/dev/null || echo "0")

# Time entries
TIME_ENTRIES=$(jq -c '[.time_entries[] | {hours: .hours, activity: .activity.name, user: .user.name, comments: .comments}]' \
  /tmp/_cpwa_time.json 2>/dev/null || echo '[]')
DESIGN_HOURS=$(jq '[.time_entries[] | select(.activity.name | ascii_downcase | contains("design")) | .hours] | add // 0' \
  /tmp/_cpwa_time.json 2>/dev/null || echo "0")
TOTAL_HOURS=$(jq '[.time_entries[].hours] | add // 0' /tmp/_cpwa_time.json 2>/dev/null || echo "0")

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Build result JSON
jq -n \
  --argjson log_agg_id "$LOG_AGG_ID" \
  --arg log_agg_status "$LOG_AGG_STATUS" \
  --arg log_agg_assignee "$LOG_AGG_ASSIGNEE" \
  --argjson log_agg_assignee_id "$LOG_AGG_ASSIGNEE_ID" \
  --argjson log_agg_est_hours "$LOG_AGG_EST_HOURS" \
  --argjson log_agg_comments "$LOG_AGG_COMMENTS" \
  --arg baseline_assignee "$BASELINE_ASSIGNEE" \
  --argjson baseline_est_hours "$BASELINE_EST_HOURS" \
  --argjson time_entries "$TIME_ENTRIES" \
  --argjson design_hours "$DESIGN_HOURS" \
  --argjson total_hours "$TOTAL_HOURS" \
  --argjson task_start "$TASK_START" \
  '{
    task_start_timestamp: $task_start,
    log_aggregation_issue: {
      id: $log_agg_id,
      status: $log_agg_status,
      assignee_name: $log_agg_assignee,
      assignee_id: $log_agg_assignee_id,
      estimated_hours: $log_agg_est_hours,
      comments: $log_agg_comments
    },
    baseline: {
      assignee: $baseline_assignee,
      estimated_hours: $baseline_est_hours
    },
    time_entries: $time_entries,
    design_hours_logged: $design_hours,
    total_hours_logged: $total_hours
  }' > "$RESULT_FILE"

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="
