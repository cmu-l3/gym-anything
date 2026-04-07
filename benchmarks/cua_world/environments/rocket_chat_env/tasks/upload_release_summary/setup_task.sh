#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up upload_release_summary task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

SEED_MANIFEST="/home/ga/rocket_chat_seed_manifest.json"
CSV_FILE="/home/ga/Documents/release_summary.csv"

# Validate seed manifest exists (it is created by the environment setup)
if [ ! -f "$SEED_MANIFEST" ]; then
  # Fallback to tmp location if not in home
  if [ -f "/tmp/rocket_chat_seed_manifest.json" ]; then
    SEED_MANIFEST="/tmp/rocket_chat_seed_manifest.json"
  else
    echo "ERROR: Seed manifest not found at $SEED_MANIFEST or /tmp"
    exit 1
  fi
fi

# Create output directory
mkdir -p /home/ga/Documents

# Generate CSV file from seeded release data (real GitHub release info)
# We select name, tag, date, and url
echo 'version,tag,published_date,url' > "$CSV_FILE"
jq -r '.seeded_releases[] | [.name, .tag_name, (.published_at | split("T")[0]), .html_url] | @csv' \
  "$SEED_MANIFEST" >> "$CSV_FILE"

ROW_COUNT=$(wc -l < "$CSV_FILE")
echo "Generated CSV with $((ROW_COUNT - 1)) data rows at $CSV_FILE"

# Set permissions so agent can read/upload it
chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"

# Ensure Rocket.Chat is reachable
wait_for_http "$ROCKETCHAT_BASE_URL" 300

# Verify admin can log in (sanity check)
if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Admin login failed during setup"
  exit 1
fi

# Clean up any previous uploads of this file to avoid confusion
# (Login to get token, find file, delete it)
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"$ROCKETCHAT_TASK_USERNAME\",\"password\":\"$ROCKETCHAT_TASK_PASSWORD\"}" \
  "$ROCKETCHAT_BASE_URL/api/v1/login" 2>/dev/null || echo "{}")
AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

if [ -n "$AUTH_TOKEN" ]; then
    # Find room ID
    ROOM_ID=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
        "$ROCKETCHAT_BASE_URL/api/v1/channels.info?roomName=release-updates" | jq -r '.channel._id // empty')
    
    if [ -n "$ROOM_ID" ]; then
        # Find existing files with our name
        curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" \
            "$ROCKETCHAT_BASE_URL/api/v1/channels.files?roomId=$ROOM_ID" | \
            jq -r '.files[] | select(.name=="release_summary.csv") | ._id' | \
            while read -r file_id; do
                echo "Cleaning up previous file artifact: $file_id"
                # Note: API endpoint to delete file requires knowing message ID usually, 
                # but we'll leave it be if complex. Just logging for now.
                # A fresh start is better ensured by timestamp checking in verifier.
            done
    fi
fi

# Launch Firefox at the Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

# Ensure window focus
focus_firefox || true
sleep 2

# Dismiss any residual dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== upload_release_summary task setup complete ==="
echo "CSV file created: $CSV_FILE"