#!/bin/bash
set -euo pipefail

echo "=== Exporting publish_acronym_glossary result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Query MongoDB for the channel
ROOM_JSON=$(docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" \
  --eval 'var r = db.rocketchat_room.findOne({name: "glossary", t: "c"}); if(r) print(JSON.stringify(r));' | grep "{" || echo "{}")

ROOM_ID=$(echo "$ROOM_JSON" | jq -r '._id // empty')

# Query MongoDB for the last message in that channel
MSG_JSON="{}"
MSG_TS="0"

if [ -n "$ROOM_ID" ]; then
    # Get the most recent non-system message
    MSG_JSON_RAW=$(docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" \
      --eval 'var m = db.rocketchat_message.find({rid: "'$ROOM_ID'", t: {$exists: false}}).sort({ts: -1}).limit(1).toArray()[0]; if(m) print(JSON.stringify(m));' | grep "{" || echo "{}")
    
    if [ "$MSG_JSON_RAW" != "{}" ]; then
        MSG_JSON="$MSG_JSON_RAW"
        
        # Convert Mongo ISO date to unix timestamp for anti-gaming comparison
        MSG_TS_RAW=$(echo "$MSG_JSON" | jq -r '.ts.$date // empty')
        if [ -n "$MSG_TS_RAW" ] && [ "$MSG_TS_RAW" != "null" ]; then
            MSG_TS=$(date -d "$MSG_TS_RAW" +%s 2>/dev/null || echo "0")
        fi
    fi
fi

# Safely create JSON result using jq to handle escaping of markdown text
jq -n \
  --arg start "$TASK_START" \
  --arg rid "$ROOM_ID" \
  --arg msg "$(echo "$MSG_JSON" | jq -r '.msg // empty')" \
  --arg ts "$MSG_TS" \
  '{
    task_start: $start|tonumber, 
    room_id: $rid, 
    message_text: $msg, 
    message_ts: $ts|tonumber, 
    screenshot_path: "/tmp/task_end.png"
  }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="