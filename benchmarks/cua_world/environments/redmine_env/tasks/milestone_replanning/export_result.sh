#!/bin/bash
echo "=== Exporting milestone_replanning result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/milestone_replanning_result.json"
API_KEY=$(redmine_admin_api_key)
BASE_URL="http://localhost:3000"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo '{"error":"no_api_key"}' > "$RESULT_FILE"
  exit 0
fi

# Get issue IDs from seed result
LOG_AGG_ID=$(redmine_issue_id_by_subject "centralized log aggregation")
K8S_ID=$(redmine_issue_id_by_subject "Kubernetes cluster for production")

echo "Log aggregation issue ID: $LOG_AGG_ID"
echo "Kubernetes issue ID: $K8S_ID"

if [ -z "$LOG_AGG_ID" ] || [ "$LOG_AGG_ID" = "null" ]; then
  echo '{"error":"log_agg_issue_not_found"}' > "$RESULT_FILE"
  exit 0
fi
if [ -z "$K8S_ID" ] || [ "$K8S_ID" = "null" ]; then
  echo '{"error":"k8s_issue_not_found"}' > "$RESULT_FILE"
  exit 0
fi

# Fetch both issues
curl -sf "${BASE_URL}/issues/${LOG_AGG_ID}.json?key=${API_KEY}&include=journals" \
  > /tmp/_mr_log_agg.json 2>/dev/null || echo '{"issue":{}}' > /tmp/_mr_log_agg.json

curl -sf "${BASE_URL}/issues/${K8S_ID}.json?key=${API_KEY}&include=journals" \
  > /tmp/_mr_k8s.json 2>/dev/null || echo '{"issue":{}}' > /tmp/_mr_k8s.json

# Fetch infra-devops issues to find the scope change notification issue
curl -sf "${BASE_URL}/issues.json?project_id=infra-devops&key=${API_KEY}&status_id=*&limit=100" \
  > /tmp/_mr_infra_issues.json 2>/dev/null || echo '{"issues":[]}' > /tmp/_mr_infra_issues.json

# Extract log aggregation fields
LOG_AGG_VERSION=$(jq -r '.issue.fixed_version.name // "none"' /tmp/_mr_log_agg.json)
LOG_AGG_PRIORITY=$(jq -r '.issue.priority.name // "unknown"' /tmp/_mr_log_agg.json)

# Extract K8s fields
K8S_PRIORITY=$(jq -r '.issue.priority.name // "unknown"' /tmp/_mr_k8s.json)
K8S_COMMENTS=$(jq -c '[.issue.journals[] | select(.notes != "") | .notes]' \
  /tmp/_mr_k8s.json 2>/dev/null || echo '[]')

# Find scope change notification issue
SCOPE_CHANGE_ISSUE=$(jq -c '
  .issues[]
  | select(
      (.subject | ascii_downcase | contains("scope change")) or
      (.subject | ascii_downcase | contains("q1 2025 sprint")) or
      (.subject | ascii_downcase | contains("sprint scope"))
    )
  | {id: .id, subject: .subject, status: .status.name, priority: .priority.name,
     assigned_to: (.assigned_to.name // "none"),
     fixed_version: (.fixed_version.name // "none"),
     tracker: .tracker.name}
' /tmp/_mr_infra_issues.json 2>/dev/null | head -1)

if [ -z "$SCOPE_CHANGE_ISSUE" ]; then
  SCOPE_CHANGE_ISSUE='null'
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
BASELINE_LOG_AGG=$(cat /tmp/task_baseline_log_agg_milestone.json 2>/dev/null || echo '{}')
BASELINE_K8S=$(cat /tmp/task_baseline_k8s.json 2>/dev/null || echo '{}')

# Build result JSON
jq -n \
  --argjson log_agg_id "$LOG_AGG_ID" \
  --arg log_agg_version "$LOG_AGG_VERSION" \
  --arg log_agg_priority "$LOG_AGG_PRIORITY" \
  --argjson k8s_id "$K8S_ID" \
  --arg k8s_priority "$K8S_PRIORITY" \
  --argjson k8s_comments "$K8S_COMMENTS" \
  --argjson scope_change_issue "$SCOPE_CHANGE_ISSUE" \
  --argjson task_start "$TASK_START" \
  --argjson baseline_log_agg "$BASELINE_LOG_AGG" \
  --argjson baseline_k8s "$BASELINE_K8S" \
  '{
    task_start_timestamp: $task_start,
    log_aggregation_issue: {
      id: $log_agg_id,
      current_version: $log_agg_version,
      current_priority: $log_agg_priority,
      baseline: $baseline_log_agg
    },
    kubernetes_issue: {
      id: $k8s_id,
      current_priority: $k8s_priority,
      comments: $k8s_comments,
      baseline: $baseline_k8s
    },
    scope_change_issue: $scope_change_issue
  }' > "$RESULT_FILE"

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="
