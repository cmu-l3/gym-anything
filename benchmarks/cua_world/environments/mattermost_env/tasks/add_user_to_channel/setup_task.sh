#!/bin/bash
set -euo pipefail

echo "=== Setting up add_user_to_channel task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Verify Mattermost API is reachable
if ! wait_for_http "${MATTERMOST_BASE_URL}/api/v4/system/ping" 600; then
  echo "ERROR: Mattermost API is not reachable at ${MATTERMOST_BASE_URL}"
  exit 1
fi

# Verify login credentials work
for _ in $(seq 1 60); do
  if mm_api_login "$MATTERMOST_TASK_USERNAME" "$MATTERMOST_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! mm_api_login "$MATTERMOST_TASK_USERNAME" "$MATTERMOST_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

echo "Ensuring qa.tester user exists and is NOT in release-updates channel..."
AUTH_TOKEN=$(mm_get_auth_token "$MATTERMOST_TASK_USERNAME" "$MATTERMOST_TASK_PASSWORD" || true)

if [ -z "$AUTH_TOKEN" ]; then
  echo "ERROR: Could not obtain auth token"
  exit 1
fi

# Get team ID
TEAM_INFO=$(curl -sS \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  "${MATTERMOST_BASE_URL}/api/v4/teams/name/main-team" 2>/dev/null || true)
TEAM_ID=$(echo "$TEAM_INFO" | jq -r '.id // empty' 2>/dev/null || true)

if [ -z "$TEAM_ID" ]; then
  echo "ERROR: Could not find main-team"
  exit 1
fi

# Create or find qa.tester user
# Check user existence by HTTP status code (not response body .id which contains error codes)
QA_USER_HTTP=$(curl -sS -o /tmp/qa_user_check.json -w "%{http_code}" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  "${MATTERMOST_BASE_URL}/api/v4/users/username/qa.tester" 2>/dev/null || echo "000")

if [ "$QA_USER_HTTP" = "200" ]; then
  QA_USER_ID=$(jq -r '.id // empty' /tmp/qa_user_check.json 2>/dev/null || true)
  echo "qa.tester user exists: $QA_USER_ID"
else
  echo "Creating qa.tester user (lookup returned HTTP $QA_USER_HTTP)..."
  CREATE_RESP=$(curl -sS -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"email":"qa.tester@mattermost.local","username":"qa.tester","password":"QaTester123!","first_name":"QA","last_name":"Tester"}' \
    "${MATTERMOST_BASE_URL}/api/v4/users" 2>/dev/null || true)
  QA_USER_ID=$(echo "$CREATE_RESP" | jq -r '.id // empty' 2>/dev/null || true)

  # Verify the ID is a real UUID, not an error code
  if [ -z "$QA_USER_ID" ] || echo "$QA_USER_ID" | grep -q "error"; then
    echo "ERROR: Could not create qa.tester user"
    echo "Response: $CREATE_RESP"
    exit 1
  fi
  echo "Created qa.tester user: $QA_USER_ID"
fi

# Add qa.tester to the team (if not already)
curl -sS -X POST \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"team_id\":\"$TEAM_ID\",\"user_id\":\"$QA_USER_ID\"}" \
  "${MATTERMOST_BASE_URL}/api/v4/teams/${TEAM_ID}/members" >/dev/null 2>&1 || true
echo "qa.tester added to main-team"

# Get release-updates channel ID
CHANNEL_INFO=$(curl -sS \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  "${MATTERMOST_BASE_URL}/api/v4/teams/${TEAM_ID}/channels/name/release-updates" 2>/dev/null || true)
CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.id // empty' 2>/dev/null || true)

if [ -z "$CHANNEL_ID" ]; then
  echo "ERROR: Could not find release-updates channel"
  exit 1
fi

# Remove qa.tester from release-updates channel if they are already a member
MEMBER_CHECK=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  "${MATTERMOST_BASE_URL}/api/v4/channels/${CHANNEL_ID}/members/${QA_USER_ID}" 2>/dev/null || echo "000")

if [ "$MEMBER_CHECK" = "200" ]; then
  echo "Removing qa.tester from release-updates channel..."
  curl -sS -X DELETE \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    "${MATTERMOST_BASE_URL}/api/v4/channels/${CHANNEL_ID}/members/${QA_USER_ID}" >/dev/null 2>&1 || true
  echo "Removed qa.tester from release-updates."
else
  echo "qa.tester is not in release-updates (good)."
fi

# Verify the user is not in the channel
VERIFY_CHECK=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  "${MATTERMOST_BASE_URL}/api/v4/channels/${CHANNEL_ID}/members/${QA_USER_ID}" 2>/dev/null || echo "000")
echo "Post-cleanup membership check: HTTP $VERIFY_CHECK (expected: 404)"

# Start Firefox at Mattermost login page
if ! restart_firefox "$MATTERMOST_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$MATTERMOST_LOGIN_URL"
sleep 2
focus_firefox || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
