#!/bin/bash
set -euo pipefail

echo "=== Setting up client_churn_risk_escalation task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="client_churn_risk_escalation"

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

# Create internal team members
create_user_if_not_exists "cs.manager" "Olivia Martins - Customer Success Manager" "olivia.m@techplatform.io"
create_user_if_not_exists "vp.sales" "Brett Holloway - VP Sales" "brett.h@techplatform.io"
create_user_if_not_exists "cto.internal" "Ingrid Johansson - CTO" "ingrid.j@techplatform.io"
create_user_if_not_exists "product.lead" "Kwame Asante - Product Lead" "kwame.a@techplatform.io"
create_user_if_not_exists "exec.sponsor" "Robert Chen - CEO" "robert.c@techplatform.io"
create_user_if_not_exists "support.lead" "Priya Nair - Support Lead" "priya.n@techplatform.io"
create_user_if_not_exists "solutions.eng" "Tom Bergmann - Solutions Engineer" "tom.b@techplatform.io"

# Clean up any pre-existing escalation channels
for ch in "meridian-escalation" "meridian-retention" "account-escalation" "churn-risk" "client-retention"; do
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

# Create #customer-success channel
CS_RESP=$(rc_api POST "channels.create" \
  '{"name":"customer-success","members":["cs.manager","vp.sales","support.lead","solutions.eng","exec.sponsor"],"readOnly":false}')
CS_ID=$(echo "$CS_RESP" | jq -r '.channel._id // empty')
if [ -z "$CS_ID" ]; then
  CS_INFO=$(rc_api GET "channels.info?roomName=customer-success")
  CS_ID=$(echo "$CS_INFO" | jq -r '.channel._id // empty')
fi

CS_MSG1_ID=""
CS_MSG2_ID=""

if [ -n "$CS_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#customer-success","text":"Health score update: Meridian Financial Group has dropped to RED (23/100) for the first time. Last login by their team: 11 days ago. Feature adoption: 12% (was 67% six months ago). They have 4 open support tickets from the past 3 weeks — two are Sev-1 and unresolved (P1-4821: bulk export broken for 10k+ records, P1-4898: SSO integration failing for 30% of users)."}' >/dev/null

  sleep 0.3
  CS_MSG1_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#customer-success","text":"@admin Meridian CS note: Their VP of Operations (Diana Walsh) called me directly this morning. She is not happy. Exact quote: \"We are evaluating alternatives. Your platform has cost our ops team 200 hours in workarounds over the past 6 weeks and we cannot justify renewing at the current contract value.\" Renewal is in 47 days ($1.2M ARR). She expects a written response plan from your leadership by end of day. I told her we would respond. @vp.sales @exec.sponsor this needs to be escalated immediately."}')
  CS_MSG1_ID=$(echo "$CS_MSG1_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#customer-success","text":"Background context: Meridian was a design partner for our enterprise analytics module launch in Q3. They provided significant input on the roadmap and expected those commitments to be delivered in Q4. Three of the five promised features were delayed to Q2 next year. This is a trust issue, not just a bug issue."}' >/dev/null

  sleep 0.3
  CS_MSG2_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#customer-success","text":"@admin — here is what Meridian needs to see to stay: (1) Sev-1 tickets P1-4821 and P1-4898 resolved within 48 hours, (2) a roadmap commitment letter signed by our CTO confirming Q2 delivery of the 3 delayed features, (3) a retention credit offer (their benchmark: 2-3 months of service credit), (4) an exec-to-exec call between Robert and their CEO (Marcus Webb) before their board meeting on March 14. If we cannot deliver all four, they will issue a 30-day notice. @admin please own this."}')
  CS_MSG2_ID=$(echo "$CS_MSG2_RESP" | jq -r '.message._id // empty')
fi

# Create #sales-enterprise channel
SE_RESP=$(rc_api POST "channels.create" \
  '{"name":"sales-enterprise","members":["vp.sales","exec.sponsor","solutions.eng","cs.manager"],"readOnly":false}')
SE_ID=$(echo "$SE_RESP" | jq -r '.channel._id // empty')
if [ -z "$SE_ID" ]; then
  SE_INFO=$(rc_api GET "channels.info?roomName=sales-enterprise")
  SE_ID=$(echo "$SE_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$SE_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#sales-enterprise","text":"@vp.sales — Meridian is in our top 5 by ARR. If we lose them it is a miss for Q2 and will affect our Series C narrative. @admin is handling the immediate response but this needs executive visibility. I am blocking time on Robert'\''s calendar for an emergency call with their CEO if we can set one up."}' >/dev/null

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#sales-enterprise","text":"Competitive intel: Meridian has been in demo calls with Vanta and our competitor DataOps Pro over the past 3 weeks. Their procurement team was spotted in DataOps Pro'\''s customer community forum. This is serious."}' >/dev/null
fi

# Create #product-feedback channel
PF_RESP=$(rc_api POST "channels.create" \
  '{"name":"product-feedback","members":["product.lead","cto.internal","solutions.eng","cs.manager"],"readOnly":false}')
PF_ID=$(echo "$PF_RESP" | jq -r '.channel._id // empty')
if [ -z "$PF_ID" ]; then
  PF_INFO=$(rc_api GET "channels.info?roomName=product-feedback")
  PF_ID=$(echo "$PF_INFO" | jq -r '.channel._id // empty')
fi

if [ -n "$PF_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#product-feedback","text":"Meridian has submitted 14 product feedback items in the past 2 months. The 3 delayed features (bulk export optimization, SSO multi-tenant support, audit log streaming) were all on their Q4 commitment list. @product.lead @cto.internal we need to figure out what we can actually commit to for them in writing."}' >/dev/null
fi

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "cs_channel_id": "${CS_ID:-}",
  "cs_msg1_id": "${CS_MSG1_ID:-}",
  "cs_msg2_id": "${CS_MSG2_ID:-}",
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
echo "CS channel msg IDs: ${CS_MSG1_ID:-none}, ${CS_MSG2_ID:-none}"
