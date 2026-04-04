#!/bin/bash
set -euo pipefail

echo "=== Setting up devops_postmortem_action_items task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="devops_postmortem_action_items"

rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken')
USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get auth token"
  exit 1
fi

rc_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  fi
}

create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="$3"
  rc_api POST "users.create" \
    "{\"username\":\"${username}\",\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"UserPass123!\",\"verified\":true,\"roles\":[\"user\"],\"joinDefaultChannels\":false,\"requirePasswordChange\":false,\"sendWelcomeEmail\":false}" >/dev/null 2>&1 || true
  echo "Ensured user: $username"
}

# Create team members
create_user_if_not_exists "sre.lead" "Priya Ramachandran - SRE Lead" "priya.r@techcorp.io"
create_user_if_not_exists "backend.dev" "James O'Brien - Backend Dev" "james.ob@techcorp.io"
create_user_if_not_exists "platform.eng" "Ana Kowalski - Platform Engineering" "ana.k@techcorp.io"
create_user_if_not_exists "frontend.dev" "Carlos Vega - Frontend Dev" "carlos.v@techcorp.io"
create_user_if_not_exists "ops.lead" "Rachel Stern - VP Engineering" "rachel.s@techcorp.io"
create_user_if_not_exists "devops.eng" "Sam Nguyen - DevOps Engineer" "sam.n@techcorp.io"
create_user_if_not_exists "dba.eng" "Mohammed Al-Rashid - Database Engineer" "mohammed.a@techcorp.io"

# Delete any pre-existing tracking channels to ensure clean state
for ch in "postmortem-tracking" "action-items" "sre-action-items" "pm-followup" "postmortem-followup"; do
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

# Create #engineering-postmortems (where review findings were posted)
PM_RESP=$(rc_api POST "channels.create" \
  '{"name":"engineering-postmortems","members":["sre.lead","backend.dev","platform.eng","frontend.dev","ops.lead","devops.eng","dba.eng"],"readOnly":false}')
PM_ID=$(echo "$PM_RESP" | jq -r '.channel._id // empty')
if [ -z "$PM_ID" ]; then
  PM_INFO=$(rc_api GET "channels.info?roomName=engineering-postmortems")
  PM_ID=$(echo "$PM_INFO" | jq -r '.channel._id // empty')
fi

PM_MSG1_ID=""
PM_MSG2_ID=""
PM_MSG3_ID=""

if [ -n "$PM_ID" ]; then
  sleep 0.3
  # Postmortem 1: DB failover incident
  PM_MSG1_RESP=$(rc_api POST "chat.postMessage" \
    "{\"channel\":\"#engineering-postmortems\",\"text\":\"## Postmortem: Database Failover Failure (INC-2024-047) - 2026-02-03\n\n**Duration:** 47 minutes (14:22 - 15:09 UTC)\n**Severity:** P1 — customer-facing checkout flow down, estimated ~\$180K revenue impact\n**Detection:** PagerDuty alert triggered 8 minutes after initial failure\n\n**Root Cause:** Primary PostgreSQL node (db-prod-01) crashed due to OOM. Automatic failover to replica (db-prod-02) did NOT execute because the replication lag exceeded the configured max_lag threshold (set to 0 bytes — effectively disabling failover). This misconfiguration was introduced during the Nov 2025 database upgrade.\n\n**Contributing Factors:**\n- Replication lag threshold had never been reviewed post-upgrade\n- Runbook for manual failover was last updated 2022, references decommissioned servers\n- On-call engineer had no prior experience with failover procedure\n- Memory alerts were firing for 6 days but categorized as non-actionable in Opsgenie\n\n**Action Items (Unresolved):**\n1. Fix PostgreSQL replication failover config and validate in staging — Owner: @backend.dev, Priority: Critical\n2. Update DB failover runbook with current server inventory — Owner: @dba.eng, Priority: High\n3. Audit alert routing rules in Opsgenie — memory alerts should route to db team — Owner: @sre.lead, Priority: High\n4. Implement pre-upgrade config review checklist for database changes — Owner: @platform.eng, Priority: Medium\n\n*This postmortem was finalized 2026-02-05. Action item tracking is TBD.*\"}")
  PM_MSG1_ID=$(echo "$PM_MSG1_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  # Postmortem 2: CDN misconfiguration
  PM_MSG2_RESP=$(rc_api POST "chat.postMessage" \
    "{\"channel\":\"#engineering-postmortems\",\"text\":\"## Postmortem: CDN Cache Purge Incident (INC-2024-061) - 2026-02-14\n\n**Duration:** 2 hours 18 minutes (09:04 - 11:22 UTC)\n**Severity:** P2 — stale content served to 34% of users, corrupted JS bundle caused app crashes for EU customers\n**Detection:** Customer support ticket spike; no automated detection triggered\n\n**Root Cause:** Emergency cache purge script (purge_cdn.sh) had a regex bug introduced in a refactor. Instead of purging only /assets/, it matched and purged ALL cached routes including authenticated session tokens. EU customers were effectively logged out mid-session.\n\n**Contributing Factors:**\n- CDN purge script had no test coverage\n- Change was deployed Friday afternoon without code review (deploy freeze exception)\n- Monitoring dashboard for CDN cache hit rate was broken for 3 weeks, unnoticed\n- Rollback procedure required manual Cloudflare dashboard access; only 2 engineers have credentials\n\n**Action Items (Unresolved):**\n1. Add unit + integration tests for CDN purge script — Owner: @platform.eng, Priority: Critical\n2. Restore CDN cache hit rate monitoring dashboard — Owner: @frontend.dev, Priority: High\n3. Expand Cloudflare access credentials to on-call rotation — Owner: @ops.lead, Priority: High\n4. Enforce code review requirement for deploy freeze exceptions — Owner: @ops.lead, Priority: Medium\n\n*This postmortem was finalized 2026-02-18. Action item owners have been verbally notified but no deadlines set.*\"}")
  PM_MSG2_ID=$(echo "$PM_MSG2_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  # Postmortem 3: Alert storm / on-call burnout
  PM_MSG3_RESP=$(rc_api POST "chat.postMessage" \
    "{\"channel\":\"#engineering-postmortems\",\"text\":\"## Postmortem: Alert Storm + Missed SLO Breach (INC-2024-079) - 2026-02-22\n\n**Duration:** 4 hours 50 minutes (03:15 - 08:05 UTC)\n**Severity:** P2 — API latency SLO breached (p99 > 2s for 4h+), 3 enterprise customers triggered SLA review clauses\n**Detection:** Automated: yes (03:17). Response delayed: on-call engineer was paged 847 times over the preceding 72 hours and had silenced PagerDuty.\n\n**Root Cause:** Memory leak in the recommendations microservice caused gradual p99 degradation. Alert storm from unrelated noisy monitor (disk inode alerts on log rotation hosts) had saturated the on-call engineer for 3 days prior, leading to alert silencing.\n\n**Contributing Factors:**\n- 847 non-actionable pages in 72h with no escalation or remediation\n- No alert quality SLO or review process\n- Recommendations service memory profiling had been deprioritized for 4 sprints\n- No escalation path when primary on-call is overloaded\n\n**Action Items (Unresolved):**\n1. Audit all PagerDuty policies and eliminate/tune noisy non-actionable monitors — Owner: @sre.lead, Priority: Critical\n2. Profile and fix memory leak in recommendations service — Owner: @backend.dev, Priority: Critical\n3. Define and enforce alert quality SLO (max X pages/on-call shift) — Owner: @sre.lead, Priority: High\n4. Create escalation runbook for overloaded on-call scenarios — Owner: @devops.eng, Priority: Medium\n\n*This postmortem was finalized 2026-02-25. REMINDER: These items have NOT been tracked in any ticketing system yet.*\"}")
  PM_MSG3_ID=$(echo "$PM_MSG3_RESP" | jq -r '.message._id // empty')
fi

# Create #sre-on-call channel — shows ongoing pain from unresolved items
SRE_RESP=$(rc_api POST "channels.create" \
  '{"name":"sre-on-call","members":["sre.lead","backend.dev","platform.eng","devops.eng","ops.lead"],"readOnly":false}')
SRE_ID=$(echo "$SRE_RESP" | jq -r '.channel._id // empty')
if [ -z "$SRE_ID" ]; then
  SRE_INFO=$(rc_api GET "channels.info?roomName=sre-on-call")
  SRE_ID=$(echo "$SRE_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$SRE_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#sre-on-call","text":"@sre.lead just had another OOM event on db-prod-03. failover did NOT trigger again. pretty sure this is the same bug from the Feb 3rd postmortem. did anyone fix the replication threshold config yet?"}' >/dev/null

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#sre-on-call","text":"no, its still open. i assumed @backend.dev was working on it but not sure. theres no ticket anywhere that i can find. same with the opsgenie audit — never happened"}' >/dev/null

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#sre-on-call","text":"@ops.lead FYI: three of the postmortem action items from last month are sitting unowned with no deadlines. high risk of repeat incidents. the db failover bug in particular. someone needs to drive this"}' >/dev/null

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#sre-on-call","text":"@admin is this something you can help track down? who owns what and make sure everyone knows their deadlines? @ops.lead needs visibility too"}' >/dev/null
fi

# Create #engineering-general for additional context
EG_RESP=$(rc_api POST "channels.create" \
  '{"name":"engineering-general","members":["sre.lead","backend.dev","platform.eng","frontend.dev","ops.lead","devops.eng","dba.eng"],"readOnly":false}')
EG_ID=$(echo "$EG_RESP" | jq -r '.channel._id // empty')
if [ -z "$EG_ID" ]; then
  EG_INFO=$(rc_api GET "channels.info?roomName=engineering-general")
  EG_ID=$(echo "$EG_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$EG_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#engineering-general","text":"Reminder: We had three P1/P2 incidents in February. The postmortems are published in #engineering-postmortems but none of the action items have been tracked or assigned deadlines. @ops.lead is asking for a status report next week. Someone needs to own getting this organized."}' >/dev/null
fi

# Record baseline state AFTER seeding (agent should not get credit for seeded channels)
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "pm_channel_id": "${PM_ID:-}",
  "sre_oncall_id": "${SRE_ID:-}",
  "pm_msg1_id": "${PM_MSG1_ID:-}",
  "pm_msg2_id": "${PM_MSG2_ID:-}",
  "pm_msg3_id": "${PM_MSG3_ID:-}",
  "action_owners": ["sre.lead", "backend.dev", "platform.eng", "frontend.dev", "ops.lead", "devops.eng", "dba.eng"],
  "baseline_groups": ${BASELINE_GROUPS}
}
EOF

date +%s > "/tmp/${TASK_NAME}_start_ts"

if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot "/tmp/${TASK_NAME}_start.png"

echo "=== Setup complete ==="
echo "PM postmortem msg IDs: ${PM_MSG1_ID:-none}, ${PM_MSG2_ID:-none}, ${PM_MSG3_ID:-none}"
