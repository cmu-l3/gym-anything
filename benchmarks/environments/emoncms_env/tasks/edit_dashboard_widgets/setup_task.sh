#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Edit Dashboard Widgets Task ==="

# 1. Wait for Emoncms
wait_for_emoncms

# 2. Generate Feeds and Data
# We use Python to interact with the API to ensure feeds are created properly with data
cat > /tmp/setup_feeds.py << 'PYEOF'
import urllib.request
import urllib.parse
import json
import time
import sys
import random

# Get API Keys
try:
    with open('/home/ga/emoncms_apikeys.sh') as f:
        content = f.read()
        for line in content.splitlines():
            if 'EMONCMS_APIKEY_WRITE' in line:
                apikey = line.split('=')[1].strip().strip('"')
except:
    print("Could not read API key")
    sys.exit(1)

base_url = "http://localhost"

def api(endpoint, params):
    params['apikey'] = apikey
    query = urllib.parse.urlencode(params)
    url = f"{base_url}/{endpoint}?{query}"
    try:
        with urllib.request.urlopen(url) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        print(f"Error {endpoint}: {e}")
        return None

# Create Feeds
feeds = [
    {"name": "old_ups_power", "tag": "old_ups", "value": 0},
    {"name": "old_ups_temp", "tag": "old_ups", "value": 0},
    {"name": "old_ups_humidity", "tag": "old_ups", "value": 0},
    {"name": "server_power", "tag": "server_room", "value": 2450},
    {"name": "server_temp", "tag": "server_room", "value": 22.5},
    {"name": "server_humidity", "tag": "server_room", "value": 45}
]

feed_ids = {}

for f in feeds:
    # Check if exists
    res = api("feed/list.json", {})
    existing = next((x for x in res if x['name'] == f['name'] and x['tag'] == f['tag']), None)
    
    if existing:
        fid = existing['id']
    else:
        # Create
        res = api("feed/create.json", {"name": f['name'], "tag": f['tag'], "datatype": 1, "engine": 5, "options": '{"interval":10}'})
        fid = res['feedid']
    
    feed_ids[f['name']] = fid
    # Insert a value
    api("feed/insert.json", {"id": fid, "time": int(time.time()), "value": f['value']})
    print(f"Feed {f['name']} ID: {fid}")

# Output IDs for bash script
with open('/tmp/feed_ids.json', 'w') as f:
    json.dump(feed_ids, f)
PYEOF

python3 /tmp/setup_feeds.py

# Read Feed IDs
OLD_POWER_ID=$(jq -r '.old_ups_power' /tmp/feed_ids.json)
OLD_TEMP_ID=$(jq -r '.old_ups_temp' /tmp/feed_ids.json)
OLD_HUM_ID=$(jq -r '.old_ups_humidity' /tmp/feed_ids.json)

# 3. Create Misconfigured Dashboard
DASH_NAME="Server Room Overview"
DASH_ALIAS="server-room"

# Delete if exists
EXISTING_ID=$(db_query "SELECT id FROM dashboard WHERE name='$DASH_NAME'" 2>/dev/null)
if [ -n "$EXISTING_ID" ]; then
    echo "Deleting existing dashboard $EXISTING_ID"
    db_query "DELETE FROM dashboard WHERE id=$EXISTING_ID"
fi

# Construct Initial Dashboard JSON
# Widgets: 
# 1. Dial (type 1) -> old_ups_power
# 2. Dial (type 1) -> old_ups_temp
# 3. Text/Value (type 2) -> old_ups_humidity

# Note: Emoncms dashboard content JSON structure varies by widget type.
# Dial: { type: "dial", id: 1, options: { feedid: X, min: 0, max: 100, units: "W", name: "Label" }, ... }
# Feedvalue: { type: "feedvalue", id: 2, options: { feedid: Y, units: "C", name: "Label" }, ... }

CONTENT_JSON=$(cat <<EOF
[
  {
    "type": "dial",
    "id": 1,
    "x": 20,
    "y": 20,
    "width": 300,
    "height": 300,
    "options": {
      "feedid": "$OLD_POWER_ID",
      "min": 0,
      "max": 3000,
      "units": "W",
      "name": "UPS Power"
    }
  },
  {
    "type": "dial",
    "id": 2,
    "x": 340,
    "y": 20,
    "width": 300,
    "height": 300,
    "options": {
      "feedid": "$OLD_TEMP_ID",
      "min": 0,
      "max": 100,
      "units": "C",
      "name": "UPS Temp"
    }
  },
  {
    "type": "feedvalue",
    "id": 3,
    "x": 660,
    "y": 100,
    "width": 200,
    "height": 50,
    "options": {
      "feedid": "$OLD_HUM_ID",
      "units": "%",
      "name": "UPS Humidity"
    }
  }
]
EOF
)

# Escape JSON for SQL
SAFE_CONTENT=$(echo "$CONTENT_JSON" | jq -c . | sed "s/'/\\\\'/g")

# Insert Dashboard
echo "Creating dashboard '$DASH_NAME'..."
# 1 = admin user id
SQL="INSERT INTO dashboard (userid, name, alias, description, content, public) VALUES (1, '$DASH_NAME', '$DASH_ALIAS', 'Main Server Room Monitoring', '$SAFE_CONTENT', 0);"
docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e "$SQL"

# 4. Launch Firefox
launch_firefox_to "http://localhost/dashboard/list" 5

# 5. Timestamp and Screenshot
date +%s > /tmp/task_start_time.txt
echo "$SAFE_CONTENT" > /tmp/initial_dashboard_content.json
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="