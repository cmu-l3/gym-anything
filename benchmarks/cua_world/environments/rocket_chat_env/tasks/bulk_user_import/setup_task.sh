#!/bin/bash
set -euo pipefail

echo "=== Setting up Bulk User Import Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Rocket.Chat is ready
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Authenticate as admin to prepare environment
echo "Authenticating as admin..."
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -z "$AUTH_TOKEN" ] || [ -z "$USER_ID" ]; then
  echo "ERROR: Failed to authenticate for setup"
  exit 1
fi

# 1. Disable Email Verification (so imported users are active immediately)
echo "Disabling email verification..."
curl -sS -X POST \
  -H "X-Auth-Token: $AUTH_TOKEN" \
  -H "X-User-Id: $USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"value": false}' \
  "${ROCKETCHAT_BASE_URL}/api/v1/settings/Accounts_EmailVerification" >/dev/null 2>&1

# 2. Record initial user count
INITIAL_COUNT=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
  "${ROCKETCHAT_BASE_URL}/api/v1/users.list?count=1" | jq '.total // 0')
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_COUNT"

# 3. Create the CSV file
echo "Creating roster CSV..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/new_hires.csv << 'CSV'
Username,Full Name,Email,Password
intern.chen,Wei Chen,wei.chen@orbital.dyn,Welcome2026!
intern.rodriguez,Elena Rodriguez,elena.r@orbital.dyn,Welcome2026!
intern.kd,Kwame Diallo,kwame.d@orbital.dyn,Welcome2026!
intern.jensen,Lars Jensen,lars.j@orbital.dyn,Welcome2026!
intern.patel,Aisha Patel,aisha.p@orbital.dyn,Welcome2026!
CSV
chown ga:ga /home/ga/Documents/new_hires.csv
chmod 644 /home/ga/Documents/new_hires.csv

# 4. Clean up any previous runs (delete these users if they exist)
USERS_TO_CLEAN=("intern.chen" "intern.rodriguez" "intern.kd" "intern.jensen" "intern.patel")
for username in "${USERS_TO_CLEAN[@]}"; do
  curl -sS -X POST \
    -H "X-Auth-Token: $AUTH_TOKEN" \
    -H "X-User-Id: $USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"$username\"}" \
    "${ROCKETCHAT_BASE_URL}/api/v1/users.delete" >/dev/null 2>&1 || true
done

# 5. Launch Firefox
echo "Launching Firefox..."
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="