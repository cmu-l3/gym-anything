#!/bin/bash
set -e
echo "=== Setting up TOU Cost Analysis task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# Ensure Emoncms is running
wait_for_emoncms

# Remove any previous report
rm -f /home/ga/tou_report.json

# Ensure we have clean API keys
if [ -f /home/ga/emoncms_apikeys.sh ]; then
    source /home/ga/emoncms_apikeys.sh
else
    # Fallback if keys weren't generated in base setup
    echo "Regenerating API keys..."
    ADMIN_APIKEY_WRITE=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e "SELECT apikey_write FROM users WHERE username='admin'" | head -1)
    export EMONCMS_APIKEY_WRITE="$ADMIN_APIKEY_WRITE"
fi

echo "=== Seeding 7 days of data ==="
# We use a python script to insert realistic patterns efficiently
cat > /tmp/seed_tou_data.py << 'PYTHON_EOF'
import urllib.request
import urllib.parse
import json
import math
import time
import random
import sys
import os

BASE_URL = os.environ.get("EMONCMS_URL", "http://localhost")
APIKEY = os.environ.get("EMONCMS_APIKEY_WRITE", "")

def api_call(endpoint, params=None):
    url = f"{BASE_URL}/{endpoint}"
    if params:
        query = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in params.items())
        url = f"{url}?{query}"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        print(f"API error ({endpoint}): {e}")
        return None

# 1. Find or Create Feed
feeds = api_call("feed/list.json", {"apikey": APIKEY})
feed_id = None

if feeds:
    for f in feeds:
        if f.get("name") == "use" and f.get("tag") == "building":
            feed_id = f.get("id")
            break

if not feed_id:
    print("Creating 'use' feed...")
    res = api_call("feed/create.json", {
        "apikey": APIKEY, "name": "use", "tag": "building", 
        "datatype": 1, "engine": 5, "options": json.dumps({"interval": 10}), "unit": "W"
    })
    if res and res.get("success"):
        feed_id = res.get("feedid")

if not feed_id:
    print("Error: Could not get feed ID")
    sys.exit(1)

print(f"Target Feed ID: {feed_id}")

# 2. Insert Data
# We insert data for the last 7 days + 1 hour buffer
now = int(time.time())
start_time = now - (7 * 24 * 3600) - 3600

# Use bulk insert if possible, but standard insert is simpler to script
# To be fast, we'll insert data points every 15 minutes (900s).
# The integration will still work, just coarser.
print("Inserting data points...")

data_points = []
t = start_time
while t <= now:
    # Deterministic pattern based on time
    hour = (t % 86400) // 3600
    
    # Base load
    power = 400.0
    
    # Office hours profile (08:00 - 18:00)
    if 8 <= hour < 18:
        # Peak around noon
        power += 2000.0 * math.sin(math.pi * (hour - 8) / 10.0)
    
    # Evening usage (18:00 - 23:00)
    if 18 <= hour < 23:
        power += 1500.0 * math.sin(math.pi * (hour - 18) / 5.0)
        
    # Random noise
    power += random.uniform(-50, 50)
    power = max(0, power)
    
    # CSV format: time,value
    data_points.append(f"{t},{power:.2f}")
    t += 900 # 15 min steps

# Post in chunks to 'feed/insert.json' is point-by-point, 
# but 'input/post' allows CSV bulk if we map it? 
# Actually, feed/insert.json is single point.
# Let's use 'input/post' with a specific time? No, input/post sets time to NOW usually unless 'time' param used.
# Emoncms API supports bulk data via 'feed/insert.json' with a JSON array since recent versions, 
# but let's assume standard point-by-point might be too slow.
# 
# OPTIMIZATION: Use 'feed/update.json' with data=[[time,value],[time,value]...] if supported.
# If not, we iterate. 7 days * 24h * 4 (15min) = 672 points. This is fast enough.

count = 0
for dp in data_points:
    ts, val = dp.split(',')
    api_call("feed/insert.json", {"apikey": APIKEY, "id": feed_id, "time": ts, "value": val})
    count += 1
    if count % 100 == 0:
        print(f"  Inserted {count} points...")

print("Data seeding complete.")
with open("/tmp/tou_feed_id.txt", "w") as f:
    f.write(str(feed_id))
PYTHON_EOF

python3 /tmp/seed_tou_data.py

# Launch Firefox to the feed list
launch_firefox_to "http://localhost/feed/list" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="