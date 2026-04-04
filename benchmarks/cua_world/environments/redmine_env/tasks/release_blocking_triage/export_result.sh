#!/bin/bash
echo "=== Exporting release_blocking_triage result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/release_blocking_triage_result.json"
API_KEY=$(redmine_admin_api_key)
BASE_URL="http://localhost:3000"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo "ERROR: Could not read admin API key from seed result"
  echo '{"error":"no_api_key"}' > "$RESULT_FILE"
  exit 0
fi

# Get issue IDs from seed result
PAYMENT_GW_ID=$(redmine_issue_id_by_subject "Payment gateway timeout")
LOGIN_BTN_ID=$(redmine_issue_id_by_subject "Login button unresponsive")

echo "Payment gateway issue ID: $PAYMENT_GW_ID"
echo "Login button issue ID: $LOGIN_BTN_ID"

if [ -z "$PAYMENT_GW_ID" ] || [ "$PAYMENT_GW_ID" = "null" ]; then
  echo '{"error":"payment_gateway_issue_not_found"}' > "$RESULT_FILE"
  exit 0
fi
if [ -z "$LOGIN_BTN_ID" ] || [ "$LOGIN_BTN_ID" = "null" ]; then
  echo '{"error":"login_button_issue_not_found"}' > "$RESULT_FILE"
  exit 0
fi

# Fetch payment gateway issue with journals
curl -sf "${BASE_URL}/issues/${PAYMENT_GW_ID}.json?key=${API_KEY}&include=journals" \
  > /tmp/_rbt_payment_gw.json 2>/dev/null || echo '{"issue":{}}' > /tmp/_rbt_payment_gw.json

# Fetch login button issue with journals
curl -sf "${BASE_URL}/issues/${LOGIN_BTN_ID}.json?key=${API_KEY}&include=journals" \
  > /tmp/_rbt_login_btn.json 2>/dev/null || echo '{"issue":{}}' > /tmp/_rbt_login_btn.json

# Fetch v1.0 Launch version due date
curl -sf "${BASE_URL}/projects/phoenix-ecommerce/versions.json?key=${API_KEY}" \
  > /tmp/_rbt_versions.json 2>/dev/null || echo '{"versions":[]}' > /tmp/_rbt_versions.json

# Extract fields
PG_STATUS=$(jq -r '.issue.status.name // "unknown"' /tmp/_rbt_payment_gw.json)
PG_PRIORITY=$(jq -r '.issue.priority.name // "unknown"' /tmp/_rbt_payment_gw.json)
PG_COMMENTS=$(jq -c '[.issue.journals[] | select(.notes != "") | .notes]' /tmp/_rbt_payment_gw.json 2>/dev/null || echo '[]')

LB_STATUS=$(jq -r '.issue.status.name // "unknown"' /tmp/_rbt_login_btn.json)
LB_ASSIGNEE_NAME=$(jq -r '.issue.assigned_to.name // "none"' /tmp/_rbt_login_btn.json)
LB_ASSIGNEE_ID=$(jq -r '.issue.assigned_to.id // 0' /tmp/_rbt_login_btn.json)
LB_DUE_DATE=$(jq -r '.issue.due_date // "none"' /tmp/_rbt_login_btn.json)
LB_COMMENTS=$(jq -c '[.issue.journals[] | select(.notes != "") | .notes]' /tmp/_rbt_login_btn.json 2>/dev/null || echo '[]')

V1_DUE_DATE=$(jq -r '.versions[] | select(.name == "v1.0 Launch") | .due_date // "none"' /tmp/_rbt_versions.json 2>/dev/null || echo "none")

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Build result JSON
jq -n \
  --arg pg_status "$PG_STATUS" \
  --arg pg_priority "$PG_PRIORITY" \
  --argjson pg_comments "$PG_COMMENTS" \
  --argjson pg_id "$PAYMENT_GW_ID" \
  --arg lb_status "$LB_STATUS" \
  --arg lb_assignee_name "$LB_ASSIGNEE_NAME" \
  --argjson lb_assignee_id "$LB_ASSIGNEE_ID" \
  --arg lb_due_date "$LB_DUE_DATE" \
  --argjson lb_comments "$LB_COMMENTS" \
  --argjson lb_id "$LOGIN_BTN_ID" \
  --arg v1_due_date "$V1_DUE_DATE" \
  --argjson task_start "$TASK_START" \
  '{
    task_start_timestamp: $task_start,
    payment_gateway: {
      id: $pg_id,
      status: $pg_status,
      priority: $pg_priority,
      comments: $pg_comments
    },
    login_button: {
      id: $lb_id,
      status: $lb_status,
      assignee_name: $lb_assignee_name,
      assignee_id: $lb_assignee_id,
      due_date: $lb_due_date,
      comments: $lb_comments
    },
    v1_launch_due_date: $v1_due_date
  }' > "$RESULT_FILE"

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="
