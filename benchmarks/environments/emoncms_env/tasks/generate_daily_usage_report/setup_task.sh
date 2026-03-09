#!/bin/bash
set -e
echo "=== Setting up generate_daily_usage_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# -----------------------------------------------------------------------
# Data Generation Script
# Backfills 8 days of data for the 'use' feed to ensure we have
# 7 complete previous days.
# -----------------------------------------------------------------------
cat > /tmp/generate_history.py << 'PYTHON_EOF'
import urllib.request
import urllib.parse
import json
import time
import math
import random
import datetime
import sys

# Get API Key from environment or arg
apikey = sys.argv[1]
base_url = "http://localhost"

def api_call(endpoint, params):
    params['apikey'] = apikey
    query = urllib.parse.urlencode(params)
    url = f"{base_url}/{endpoint}?{query}"
    try:
        with urllib.request.urlopen(url) as response:
            return json.loads(response.read())
    except Exception as e:
        print(f"Error calling {endpoint}: {e}")
        return None

# 1. Create or Get Feed
feed_name = "use"
feed_tag = "Home"

# Check if feed exists
feeds = api_call("feed/list.json", {})
feed_id = None
for f in feeds:
    if f['name'] == feed_name and f['tag'] == feed_tag:
        feed_id = f['id']
        break

if not feed_id:
    print(f"Creating feed {feed_name}...")
    # Create feed (Engine 5 = PHPFina, Interval = 60s for history generation speed)
    res = api_call("feed/create.json", {
        "name": feed_name,
        "tag": feed_tag,
        "datatype": 1,
        "engine": 5, 
        "options": '{"interval":60}',
        "unit": "W"
    })
    if res and res.get('success'):
        feed_id = res['feedid']
    else:
        print("Failed to create feed")
        sys.exit(1)

print(f"Target Feed ID: {feed_id}")

# 2. Generate Data
# Generate data for the last 8 days (to ensure 7 full UTC days)
# 60s interval = 1440 points per day
now = int(time.time())
days_back = 8
start_time = now - (days_back * 86400)
interval = 300 # 5 minute resolution for speed of insertion

data_points = []
print("Generating data points...")

# Realistic usage pattern simulation
def get_power(ts):
    dt = datetime.datetime.fromtimestamp(ts)
    hour = dt.hour + dt.minute/60.0
    
    # Base load (fridge, standby)
    power = 150 + random.uniform(-20, 20)
    
    # Morning peak (07:00 - 09:00)
    if 6 <= hour <= 9:
        power += 1500 * math.exp(-((hour - 7.5)**2) / 1.5)
        
    # Evening peak (17:00 - 22:00)
    if 17 <= hour <= 22:
        power += 2000 * math.exp(-((hour - 19.5)**2) / 4)
        
    # Random spikes (kettle, microwave)
    if random.random() > 0.98:
        power += 2500
        
    return max(0, int(power))

# Batch update via feed/insert.json (can handle CSV data)
# Format: time,value
batch_size = 500
batch_data = []

current_time = start_time
while current_time < now:
    val = get_power(current_time)
    batch_data.append([current_time, val])
    
    if len(batch_data) >= batch_size:
        # Convert to JSON array format for API: [[time,value],[time,value]]
        json_str = json.dumps(batch_data)
        api_call("feed/insert.json", {"id": feed_id, "data": json_str})
        batch_data = []
        
    current_time += interval

# Send remaining
if batch_data:
    json_str = json.dumps(batch_data)
    api_call("feed/insert.json", {"id": feed_id, "data": json_str})

print("Data generation complete.")
PYTHON_EOF

# Execute data generation
APIKEY_WRITE=$(get_apikey_write)
python3 /tmp/generate_history.py "$APIKEY_WRITE"

# Launch Firefox to Feeds page
launch_firefox_to "http://localhost/feed/list" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="