#!/bin/bash
echo "=== Setting up q1_milestone_reconciliation task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Redmine is up
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

API_KEY=$(redmine_admin_api_key)
BASE_URL="http://localhost:3000"

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo "ERROR: Could not obtain admin API key"
  exit 1
fi

# ---------------------------------------------------------------------------
# Look up issue IDs for Q1 2025 Goals issues
# ---------------------------------------------------------------------------
CI_CD_ID=$(redmine_issue_id_by_subject "Migrate CI/CD from Jenkins")
K8S_ID=$(redmine_issue_id_by_subject "Kubernetes cluster for production")
STAGING_DB_ID=$(redmine_issue_id_by_subject "Staging database running out")
SSL_ID=$(redmine_issue_id_by_subject "SSL certificate for api.devlabs.io")

log "Q1 issue IDs: CI/CD=$CI_CD_ID  K8s=$K8S_ID  StagingDB=$STAGING_DB_ID  SSL=$SSL_ID"

# ---------------------------------------------------------------------------
# Look up user IDs for carol.santos and david.kim
# ---------------------------------------------------------------------------
CAROL_ID=$(curl -s "${BASE_URL}/users.json?key=${API_KEY}&name=carol" \
  | python3 -c "import sys,json
users=json.load(sys.stdin).get('users',[])
for u in users:
  if 'carol' in u.get('login',''):
    print(u['id']); break" 2>/dev/null)

DAVID_ID=$(curl -s "${BASE_URL}/users.json?key=${API_KEY}&name=david" \
  | python3 -c "import sys,json
users=json.load(sys.stdin).get('users',[])
for u in users:
  if 'david' in u.get('login',''):
    print(u['id']); break" 2>/dev/null)

log "User IDs: carol=$CAROL_ID  david=$DAVID_ID"

# ---------------------------------------------------------------------------
# Look up activity IDs for Development and Design
# ---------------------------------------------------------------------------
DEV_ACTIVITY_ID=$(curl -s "${BASE_URL}/enumerations/time_entry_activities.json?key=${API_KEY}" \
  | python3 -c "import sys,json
acts=json.load(sys.stdin).get('time_entry_activities',[])
for a in acts:
  if a['name']=='Development':
    print(a['id']); break" 2>/dev/null)

DESIGN_ACTIVITY_ID=$(curl -s "${BASE_URL}/enumerations/time_entry_activities.json?key=${API_KEY}" \
  | python3 -c "import sys,json
acts=json.load(sys.stdin).get('time_entry_activities',[])
for a in acts:
  if a['name']=='Design':
    print(a['id']); break" 2>/dev/null)

log "Activity IDs: Development=$DEV_ACTIVITY_ID  Design=$DESIGN_ACTIVITY_ID"

# ---------------------------------------------------------------------------
# Add additional time entries to make totals non-trivial
# Global seed already has: CI/CD=12h(carol), StagingDB=2h(david)
# We add: CI/CD+4h(carol), StagingDB+6h(david), K8s+3h(david), SSL+2h(carol)
# Final totals: CI/CD=16h, StagingDB=8h, K8s=3h, SSL=2h => total 29h
# ---------------------------------------------------------------------------
SPENT_DATE_3=$(date -d '-3 days' +%Y-%m-%d 2>/dev/null || date -v-3d +%Y-%m-%d)
SPENT_DATE_5=$(date -d '-5 days' +%Y-%m-%d 2>/dev/null || date -v-5d +%Y-%m-%d)
SPENT_DATE_7=$(date -d '-7 days' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)
SPENT_DATE_2=$(date -d '-2 days' +%Y-%m-%d 2>/dev/null || date -v-2d +%Y-%m-%d)

# carol.santos: +4h Development on CI/CD migration
if [ -n "$CI_CD_ID" ] && [ -n "$CAROL_ID" ] && [ -n "$DEV_ACTIVITY_ID" ]; then
  curl -s -X POST "${BASE_URL}/time_entries.json" \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: ${API_KEY}" \
    -d "{\"time_entry\":{\"issue_id\":${CI_CD_ID},\"hours\":4.0,\"activity_id\":${DEV_ACTIVITY_ID},\"user_id\":${CAROL_ID},\"spent_on\":\"${SPENT_DATE_3}\",\"comments\":\"Phase 2 migration - packaging and deployment jobs\"}}" \
    > /dev/null 2>&1
  log "Added 4.0h Development on CI/CD #${CI_CD_ID} for carol"
fi

# david.kim: +6h Development on Staging DB
if [ -n "$STAGING_DB_ID" ] && [ -n "$DAVID_ID" ] && [ -n "$DEV_ACTIVITY_ID" ]; then
  curl -s -X POST "${BASE_URL}/time_entries.json" \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: ${API_KEY}" \
    -d "{\"time_entry\":{\"issue_id\":${STAGING_DB_ID},\"hours\":6.0,\"activity_id\":${DEV_ACTIVITY_ID},\"user_id\":${DAVID_ID},\"spent_on\":\"${SPENT_DATE_5}\",\"comments\":\"Implemented automated log rotation and archival\"}}" \
    > /dev/null 2>&1
  log "Added 6.0h Development on StagingDB #${STAGING_DB_ID} for david"
fi

# david.kim: +3h Development on K8s
if [ -n "$K8S_ID" ] && [ -n "$DAVID_ID" ] && [ -n "$DEV_ACTIVITY_ID" ]; then
  curl -s -X POST "${BASE_URL}/time_entries.json" \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: ${API_KEY}" \
    -d "{\"time_entry\":{\"issue_id\":${K8S_ID},\"hours\":3.0,\"activity_id\":${DEV_ACTIVITY_ID},\"user_id\":${DAVID_ID},\"spent_on\":\"${SPENT_DATE_7}\",\"comments\":\"Initial cluster architecture design and vendor evaluation\"}}" \
    > /dev/null 2>&1
  log "Added 3.0h Development on K8s #${K8S_ID} for david"
fi

# carol.santos: +2h Design on SSL cert
if [ -n "$SSL_ID" ] && [ -n "$CAROL_ID" ] && [ -n "$DESIGN_ACTIVITY_ID" ]; then
  curl -s -X POST "${BASE_URL}/time_entries.json" \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: ${API_KEY}" \
    -d "{\"time_entry\":{\"issue_id\":${SSL_ID},\"hours\":2.0,\"activity_id\":${DESIGN_ACTIVITY_ID},\"user_id\":${CAROL_ID},\"spent_on\":\"${SPENT_DATE_2}\",\"comments\":\"Reviewed certificate renewal process and automation options\"}}" \
    > /dev/null 2>&1
  log "Added 2.0h Design on SSL #${SSL_ID} for carol"
fi

# ---------------------------------------------------------------------------
# Record baselines for all Q1 issues
# ---------------------------------------------------------------------------
for ISSUE_TUPLE in "${CI_CD_ID}:ci_cd" "${K8S_ID}:k8s" "${STAGING_DB_ID}:staging_db" "${SSL_ID}:ssl"; do
  ISSUE_ID="${ISSUE_TUPLE%%:*}"
  ISSUE_KEY="${ISSUE_TUPLE##*:}"
  if [ -n "$ISSUE_ID" ] && [ "$ISSUE_ID" != "null" ]; then
    BASELINE=$(curl -s \
      "${BASE_URL}/issues/${ISSUE_ID}.json?key=${API_KEY}&include=journals" \
      | jq '{status: .issue.status.name, priority: .issue.priority.name, version: (.issue.fixed_version.name // "none"), estimated_hours: (.issue.estimated_hours // 0), comment_count: ([.issue.journals[] | select(.notes != "")] | length)}' \
      2>/dev/null || echo '{}')
    echo "$BASELINE" > "/tmp/task_baseline_${ISSUE_KEY}.json"
    log "${ISSUE_KEY} issue #${ISSUE_ID} baseline: $BASELINE"
  fi
done

# Record time entry baselines per issue
for ISSUE_TUPLE in "${CI_CD_ID}:ci_cd" "${K8S_ID}:k8s" "${STAGING_DB_ID}:staging_db" "${SSL_ID}:ssl"; do
  ISSUE_ID="${ISSUE_TUPLE%%:*}"
  ISSUE_KEY="${ISSUE_TUPLE##*:}"
  if [ -n "$ISSUE_ID" ] && [ "$ISSUE_ID" != "null" ]; then
    HOURS=$(curl -s "${BASE_URL}/time_entries.json?key=${API_KEY}&issue_id=${ISSUE_ID}&limit=100" \
      | jq '[.time_entries[].hours] | add // 0' 2>/dev/null || echo "0")
    echo "$HOURS" > "/tmp/task_baseline_hours_${ISSUE_KEY}"
    log "${ISSUE_KEY} issue #${ISSUE_ID} total hours: $HOURS"
  fi
done

# Record Q1 version baseline
Q1_VERSION_ID=$(curl -s "${BASE_URL}/projects/infra-devops/versions.json?key=${API_KEY}" \
  | python3 -c "import sys,json
versions=json.load(sys.stdin).get('versions',[])
for v in versions:
  if 'Q1' in v.get('name',''):
    print(v['id']); break" 2>/dev/null)
echo "$Q1_VERSION_ID" > /tmp/task_baseline_q1_version_id
log "Q1 2025 Goals version ID: $Q1_VERSION_ID"

# Save issue ID mapping for export script
jq -n \
  --argjson ci_cd "${CI_CD_ID:-0}" \
  --argjson k8s "${K8S_ID:-0}" \
  --argjson staging_db "${STAGING_DB_ID:-0}" \
  --argjson ssl "${SSL_ID:-0}" \
  --argjson q1_version_id "${Q1_VERSION_ID:-0}" \
  '{ci_cd: $ci_cd, k8s: $k8s, staging_db: $staging_db, ssl: $ssl, q1_version_id: $q1_version_id}' \
  > /tmp/task_issue_ids.json

# ---------------------------------------------------------------------------
# Open Firefox at Infrastructure & DevOps project
# ---------------------------------------------------------------------------
TARGET_URL="${REDMINE_BASE_URL}/projects/infra-devops"
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
