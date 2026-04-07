#!/bin/bash
set -euo pipefail

echo "=== Exporting create_restricted_invite task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual evidence
take_screenshot /tmp/task_final.png

# 1. Use Python script to query REST API for messages
cat > /tmp/export_api.py << 'EOF'
import requests, json

base_url = "http://localhost:3000"
try:
    with open("/tmp/task_start_timestamp", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

result = {"messages": [], "task_start_timestamp": task_start}

try:
    # Login as admin to use API
    resp = requests.post(f"{base_url}/api/v1/login", json={"user": "admin", "password": "Admin1234!"})
    if resp.status_code == 200:
        data = resp.json().get("data", {})
        headers = {
            "X-Auth-Token": data.get("authToken"),
            "X-User-Id": data.get("userId"),
            "Content-Type": "application/json"
        }

        # Get channel info for target channel
        ch_resp = requests.get(f"{base_url}/api/v1/channels.info?roomName=release-updates", headers=headers)
        room_id = ch_resp.json().get("channel", {}).get("_id")

        if room_id:
            # Get latest 50 messages
            msg_resp = requests.get(f"{base_url}/api/v1/channels.history?roomId={room_id}&count=50", headers=headers)
            result["messages"] = msg_resp.json().get("messages", [])
except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/export_api.py

# 2. Use MongoDB to dump invites (robust to any undocumented API changes)
echo "Dumping invites from MongoDB..."
docker exec rc-mongodb mongosh --quiet --eval '
  var allInvites = [];
  try {
      var targetDb = db.getSiblingDB("rocketchat");
      var cols = targetDb.getCollectionNames();
      cols.forEach(function(colName) {
         if (colName.toLowerCase().indexOf("invite") !== -1) {
            targetDb.getCollection(colName).find().forEach(function(doc) {
               allInvites.push(doc);
            });
         }
      });
  } catch (e) {}
  print(JSON.stringify(allInvites));
' > /tmp/mongo_invites.json || echo "[]" > /tmp/mongo_invites.json

# Fix permissions so verifier.py can read them via copy_from_env
chmod 666 /tmp/task_result.json /tmp/mongo_invites.json /tmp/task_final.png 2>/dev/null || sudo chmod 666 /tmp/task_result.json /tmp/mongo_invites.json /tmp/task_final.png 2>/dev/null || true

echo "API and DB exports completed."
echo "=== Export complete ==="