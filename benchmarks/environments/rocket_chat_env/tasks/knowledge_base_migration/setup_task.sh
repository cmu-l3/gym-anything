#!/bin/bash
set -euo pipefail

echo "=== Setting up knowledge_base_migration task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="knowledge_base_migration"

rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then break; fi
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
      -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" -H "X-User-Id: $USERID" \
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
}

create_user_if_not_exists "junior.dev" "Junior Developer" "junior.dev@company.local"
create_user_if_not_exists "senior.dev" "Senior Developer" "senior.dev@company.local"
create_user_if_not_exists "tech.architect" "Tech Architect" "tech.architect@company.local"

# Clean up pre-existing channels
for ch in engineering-chat kb-architecture kb-api-docs kb-decisions; do
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

sleep 1

# Create #engineering-chat and seed it with a mix of casual and technical messages
rc_api POST "channels.create" \
  '{"name":"engineering-chat","members":["junior.dev","senior.dev","tech.architect"],"readOnly":false}' >/dev/null 2>&1

# Seed messages - mix of casual chat and technical content
# The agent needs to identify the technical messages and sort them into the right KB channels

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"Hey team, anyone want to grab lunch today? Thinking about that new ramen place."}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"**ADR-001: Microservices Migration Decision**\n\nStatus: Accepted\nDate: 2026-01-15\n\nContext: Our monolithic application is hitting scaling limits at 50K concurrent users. Deployment cycles take 4+ hours.\n\nDecision: We will decompose the monolith into microservices starting with the user-auth and payment modules. Each service will own its database (database-per-service pattern).\n\nConsequences:\n- Independent scaling per service\n- Need for service mesh (Istio) and API gateway\n- Team restructuring into domain-aligned squads\n- 6-month migration timeline"}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"The CI build is broken again. Can someone look at the flaky test in auth-service?"}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"**REST API v2 Endpoints Documentation**\n\nBase URL: https://api.company.com/v2\n\nAuthentication:\n- POST /auth/token - Get JWT token (body: {username, password})\n- POST /auth/refresh - Refresh expired token\n\nUser Management:\n- GET /users - List users (paginated, ?page=1&limit=20)\n- GET /users/:id - Get user details\n- PUT /users/:id - Update user profile\n- DELETE /users/:id - Deactivate user\n\nOrders:\n- POST /orders - Create order\n- GET /orders/:id - Get order status\n- PATCH /orders/:id/status - Update order status\n\nAll endpoints return JSON. Rate limit: 100 req/min per API key. Errors follow RFC 7807 Problem Details format."}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"Happy Friday everyone! :tada: Who is up for game night?"}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"**Event-Driven Architecture Design**\n\nWe are adopting an event-driven architecture for inter-service communication.\n\nEvent Bus: Apache Kafka (3-broker cluster)\nSchema Registry: Confluent Schema Registry with Avro schemas\n\nCore Events:\n- UserRegistered (user-auth -> notification-service, analytics)\n- OrderPlaced (order-service -> inventory, payment, notification)\n- PaymentProcessed (payment-service -> order-service, accounting)\n\nPatterns:\n- Event Sourcing for the order aggregate\n- CQRS for read-heavy analytics queries\n- Saga pattern for distributed transactions (order fulfillment)\n\nSLAs: 99.9% message delivery, <100ms p99 latency for critical paths."}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"Reminder: sprint retro at 3pm today. Please add your items to the Miro board."}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"@tech.architect can you review the PR for the new caching layer? PR #4521"}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"**ADR-002: API Versioning Strategy Decision**\n\nStatus: Accepted\nDate: 2026-02-01\n\nContext: We need a consistent API versioning strategy as we build v2 endpoints alongside v1.\n\nDecision: URL path versioning (/v1/, /v2/) with a 12-month deprecation policy for old versions. v1 sunset date: 2027-03-01.\n\nConsequences:\n- Clear version boundaries for consumers\n- Need API gateway routing rules per version\n- Documentation must cover both versions during overlap"}' >/dev/null
sleep 0.2

rc_api POST "chat.postMessage" \
  '{"channel":"#engineering-chat","text":"Does anyone know the wifi password for the 5th floor conference room?"}' >/dev/null

echo "Seeded 10 messages in #engineering-chat"

# Record baseline
cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s)
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

echo "=== Task setup complete ==="
