#!/bin/bash
set -euo pipefail

echo "=== Setting up create_custom_user_status task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Clean state: Remove any existing "Deploying" custom status via MongoDB
# This ensures the task starts completely fresh and the agent must actually do the work.
echo "Cleaning up any pre-existing 'Deploying' custom statuses..."
docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" \
  --eval 'db.rocketchat_custom_user_status.deleteMany({name: "Deploying"})' 2>/dev/null || true

# Start Firefox at the Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# Save screenshot for evidence
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="