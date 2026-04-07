#!/bin/bash
set -euo pipefail

echo "=== Exporting manual_message_pruning task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence/VLM
take_screenshot /tmp/task_end.png
echo "Task end screenshot saved to /tmp/task_end.png"

CHANNEL_ID=$(jq -r '.workspace.channel_id // empty' "$SEED_MANIFEST_FILE" 2>/dev/null || true)
CHANNEL_STILL_EXISTS="false"

if [ -n "$CHANNEL_ID" ]; then
  # 1. Verify the channel document hasn't been completely deleted
  ROOM_COUNT=$(docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" --eval "db.rocketchat_room.countDocuments({_id: '$CHANNEL_ID'})" 2>/dev/null || echo "0")
  if [ "$ROOM_COUNT" -gt 0 ]; then
    CHANNEL_STILL_EXISTS="true"
  fi

  # 2. Dump the final state of the messages
  docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" --eval "
    JSON.stringify(
      db.rocketchat_message.find({rid: '$CHANNEL_ID', t: {\$exists: false}})
      .toArray()
      .map(m => ({id: m._id, ts: m.ts ? m.ts.toISOString() : ''}))
    )
  " > /tmp/final_messages.json 2>/dev/null || echo "[]" > /tmp/final_messages.json
else
  echo "[]" > /tmp/final_messages.json
fi

# Fallback empty arrays if the dumps failed for any reason
if [ ! -f /tmp/initial_messages.json ]; then echo "[]" > /tmp/initial_messages.json; fi
if [ ! -f /tmp/final_messages.json ]; then echo "[]" > /tmp/final_messages.json; fi

# Create the final result JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "channel_exists": $CHANNEL_STILL_EXISTS,
  "initial_messages": $(cat /tmp/initial_messages.json),
  "final_messages": $(cat /tmp/final_messages.json)
}
EOF

# Move to the fixed location that the verifier expects
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="