#!/bin/bash
set -euo pipefail

echo "=== Setting up manual_message_pruning task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Verify login credentials work
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

# Ensure seed manifest exists locally
if [ ! -f "$SEED_MANIFEST_FILE" ] && [ -f "/home/ga/rocket_chat_seed_manifest.json" ]; then
  cp "/home/ga/rocket_chat_seed_manifest.json" "$SEED_MANIFEST_FILE"
fi

# Backdate the seeded messages based on their real GitHub release dates.
# This ensures we have a chronological history spanning 2025 and 2026
# so that the prune tool's date filters work authentically.
if [ -f "$SEED_MANIFEST_FILE" ]; then
  echo "Backdating seeded messages to their actual release dates..."
  CHANNEL_ID=$(jq -r '.workspace.channel_id // empty' "$SEED_MANIFEST_FILE")

  jq -c '.seeded_releases[]' "$SEED_MANIFEST_FILE" | while read -r rel; do
    msg_id=$(echo "$rel" | jq -r '.message_id')
    pub_at=$(echo "$rel" | jq -r '.published_at')

    if [ -n "$msg_id" ] && [ -n "$pub_at" ]; then
      echo "Backdating message $msg_id to $pub_at"
      # Update the message document in MongoDB directly
      docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" --eval "
        db.rocketchat_message.updateOne(
          {_id: '$msg_id'},
          {\$set: {ts: new ISODate('$pub_at'), _updatedAt: new ISODate('$pub_at')}}
        )
      " >/dev/null 2>&1 || true
    fi
  done

  # Export the initial state of the messages BEFORE the agent starts
  # We filter out system messages (where 't' exists) and only export standard chat messages
  docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" --eval "
    JSON.stringify(
      db.rocketchat_message.find({rid: '$CHANNEL_ID', t: {\$exists: false}})
      .toArray()
      .map(m => ({id: m._id, ts: m.ts ? m.ts.toISOString() : ''}))
    )
  " > /tmp/initial_messages.json 2>/dev/null || echo "[]" > /tmp/initial_messages.json
else
  echo "[]" > /tmp/initial_messages.json
fi

# Start Firefox at Rocket.Chat login page deterministically
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# Take an initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="