#!/bin/bash
echo "=== Exporting q1_milestone_reconciliation result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/q1_milestone_reconciliation_result.json"
API_KEY=$(redmine_admin_api_key)
BASE_URL="http://localhost:3000"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo '{"error":"no_api_key"}' > "$RESULT_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Load issue ID mapping from setup
# ---------------------------------------------------------------------------
if [ -f /tmp/task_issue_ids.json ]; then
  CI_CD_ID=$(jq -r '.ci_cd' /tmp/task_issue_ids.json)
  K8S_ID=$(jq -r '.k8s' /tmp/task_issue_ids.json)
  STAGING_DB_ID=$(jq -r '.staging_db' /tmp/task_issue_ids.json)
  SSL_ID=$(jq -r '.ssl' /tmp/task_issue_ids.json)
  Q1_VERSION_ID=$(jq -r '.q1_version_id' /tmp/task_issue_ids.json)
else
  CI_CD_ID=$(redmine_issue_id_by_subject "Migrate CI/CD from Jenkins")
  K8S_ID=$(redmine_issue_id_by_subject "Kubernetes cluster for production")
  STAGING_DB_ID=$(redmine_issue_id_by_subject "Staging database running out")
  SSL_ID=$(redmine_issue_id_by_subject "SSL certificate for api.devlabs.io")
  Q1_VERSION_ID=$(curl -s "${BASE_URL}/projects/infra-devops/versions.json?key=${API_KEY}" \
    | jq '[.versions[] | select(.name | contains("Q1"))] | .[0].id // 0' 2>/dev/null)
fi

echo "Issue IDs: CI/CD=$CI_CD_ID  K8s=$K8S_ID  StagingDB=$STAGING_DB_ID  SSL=$SSL_ID"
echo "Q1 Version ID: $Q1_VERSION_ID"

# ---------------------------------------------------------------------------
# Helper: fetch issue + time entries and produce a compact JSON object
# ---------------------------------------------------------------------------
fetch_issue_data() {
  local issue_id="$1"
  local key="$2"

  if [ -z "$issue_id" ] || [ "$issue_id" = "null" ] || [ "$issue_id" = "0" ]; then
    echo '{"id":0,"status":"unknown","priority":"unknown","subject":"unknown","assignee":"none","fixed_version":"none","estimated_hours":0,"total_hours_logged":0,"comments":[]}'
    return
  fi

  # Fetch issue with journals
  curl -sf "${BASE_URL}/issues/${issue_id}.json?key=${API_KEY}&include=journals" \
    > "/tmp/_q1r_${key}.json" 2>/dev/null \
    || echo '{"issue":{}}' > "/tmp/_q1r_${key}.json"

  # Fetch time entries
  curl -sf "${BASE_URL}/time_entries.json?key=${API_KEY}&issue_id=${issue_id}&limit=100" \
    > "/tmp/_q1r_time_${key}.json" 2>/dev/null \
    || echo '{"time_entries":[]}' > "/tmp/_q1r_time_${key}.json"

  # Extract total hours from time entries
  local total_hours
  total_hours=$(jq '[.time_entries[].hours] | add // 0' "/tmp/_q1r_time_${key}.json" 2>/dev/null || echo "0")

  # Extract issue fields + inject total_hours
  jq --argjson thours "$total_hours" --argjson iid "$issue_id" '{
    id: $iid,
    status: (.issue.status.name // "unknown"),
    priority: (.issue.priority.name // "unknown"),
    subject: (.issue.subject // "unknown"),
    assignee: (.issue.assigned_to.name // "none"),
    fixed_version: (.issue.fixed_version.name // "none"),
    estimated_hours: (.issue.estimated_hours // 0),
    total_hours_logged: $thours,
    comments: [.issue.journals[] | select(.notes != "" and .notes != null) | .notes]
  }' "/tmp/_q1r_${key}.json" 2>/dev/null || echo '{"id":'"$issue_id"',"status":"unknown","priority":"unknown","subject":"unknown","assignee":"none","fixed_version":"none","estimated_hours":0,"total_hours_logged":0,"comments":[]}'
}

# ---------------------------------------------------------------------------
# Fetch all issue data
# ---------------------------------------------------------------------------
CI_CD_DATA=$(fetch_issue_data "$CI_CD_ID" "ci_cd")
K8S_DATA=$(fetch_issue_data "$K8S_ID" "k8s")
STAGING_DB_DATA=$(fetch_issue_data "$STAGING_DB_ID" "staging_db")
SSL_DATA=$(fetch_issue_data "$SSL_ID" "ssl")

# ---------------------------------------------------------------------------
# Fetch Q1 version status
# ---------------------------------------------------------------------------
Q1_STATUS="unknown"
if [ -n "$Q1_VERSION_ID" ] && [ "$Q1_VERSION_ID" != "null" ] && [ "$Q1_VERSION_ID" != "0" ]; then
  Q1_STATUS=$(curl -sf "${BASE_URL}/versions/${Q1_VERSION_ID}.json?key=${API_KEY}" \
    | jq -r '.version.status // "unknown"' 2>/dev/null || echo "unknown")
fi

# ---------------------------------------------------------------------------
# Fetch wiki page Q1_2025_Retrospective
# ---------------------------------------------------------------------------
WIKI_HTTP_CODE=$(curl -s -o /tmp/_q1r_wiki.json -w "%{http_code}" \
  "${BASE_URL}/projects/infra-devops/wiki/Q1_2025_Retrospective.json?key=${API_KEY}" 2>/dev/null)

WIKI_EXISTS="false"
WIKI_TEXT=""
if [ "$WIKI_HTTP_CODE" = "200" ]; then
  WIKI_EXISTS="true"
  WIKI_TEXT=$(jq -r '.wiki_page.text // ""' /tmp/_q1r_wiki.json 2>/dev/null || echo "")
fi

# ---------------------------------------------------------------------------
# Load baselines
# ---------------------------------------------------------------------------
BASELINE_CI_CD=$(cat /tmp/task_baseline_ci_cd.json 2>/dev/null || echo '{}')
BASELINE_K8S=$(cat /tmp/task_baseline_k8s.json 2>/dev/null || echo '{}')
BASELINE_STAGING_DB=$(cat /tmp/task_baseline_staging_db.json 2>/dev/null || echo '{}')
BASELINE_SSL=$(cat /tmp/task_baseline_ssl.json 2>/dev/null || echo '{}')
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ---------------------------------------------------------------------------
# Assemble final result JSON
# ---------------------------------------------------------------------------
jq -n \
  --argjson task_start "$TASK_START" \
  --argjson ci_cd "$CI_CD_DATA" \
  --argjson k8s "$K8S_DATA" \
  --argjson staging_db "$STAGING_DB_DATA" \
  --argjson ssl "$SSL_DATA" \
  --argjson q1_version_id "${Q1_VERSION_ID:-0}" \
  --arg q1_status "$Q1_STATUS" \
  --arg wiki_exists "$WIKI_EXISTS" \
  --arg wiki_text "$WIKI_TEXT" \
  --argjson baseline_ci_cd "$BASELINE_CI_CD" \
  --argjson baseline_k8s "$BASELINE_K8S" \
  --argjson baseline_staging_db "$BASELINE_STAGING_DB" \
  --argjson baseline_ssl "$BASELINE_SSL" \
  '{
    task_start_timestamp: $task_start,
    issues: {
      ci_cd: $ci_cd,
      k8s: $k8s,
      staging_db: $staging_db,
      ssl: $ssl
    },
    baselines: {
      ci_cd: $baseline_ci_cd,
      k8s: $baseline_k8s,
      staging_db: $baseline_staging_db,
      ssl: $baseline_ssl
    },
    q1_version: {
      id: $q1_version_id,
      status: $q1_status
    },
    wiki: {
      exists: ($wiki_exists == "true"),
      text: $wiki_text
    }
  }' > "$RESULT_FILE"

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="
