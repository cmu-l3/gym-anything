#!/bin/bash
set -e
echo "=== Setting up find_peak_demand task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is running and reachable
wait_for_emoncms

# Generate Data and Ground Truth using Python
# We run this on the host to calculate values, then push to Emoncms via API
echo "Generating realistic feed data..."

python3 << 'EOF'
import time
import json
import random
import math
import urllib.request
import urllib.parse
import os

# Configuration
API_KEY = os.environ.get("EMONCMS_APIKEY_WRITE")
BASE_URL = os.environ.get("EMONCMS_URL")
FEED_NAME = "main_panel_power"
INTERVAL = 600  # 10 minutes
POINTS = 144    # 24 hours

def api_call(endpoint, params):
    params['apikey'] = API_KEY
    query = urllib.parse.urlencode(params)
    url = f"{BASE_URL}/{endpoint}?{query}"
    try:
        with urllib.request.urlopen(url) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        print(f"Error calling {endpoint}: {e}")
        return None

# 1. Check if feed exists, delete if so to ensure clean state
feeds = api_call("feed/list.json", {})
for feed in feeds:
    if feed['name'] == FEED_NAME:
        print(f"Deleting existing feed {feed['id']}")
        api_call("feed/delete.json", {"id": feed['id']})

# 2. Create Feed (PHPFina, 10s interval default, but we'll insert at 10m spacing)
# Note: Emoncms engine 5 is PHPFina
res = api_call("feed/create.json", {
    "name": FEED_NAME,
    "tag": "Power",
    "datatype": 1,
    "engine": 5,
    "options": json.dumps({"interval": 10}) 
})

if not res or not res.get("success"):
    print("Failed to create feed")
    exit(1)

feed_id = res["feedid"]
print(f"Created feed ID: {feed_id}")

# 3. Generate Data
end_time = int(time.time())
start_time = end_time - (POINTS * INTERVAL)
# Align start time to interval
start_time = start_time - (start_time % INTERVAL)

data_points = []
peak_value = 0.0
peak_time = 0

# Peak event parameters (e.g., at 14:00 - 15:00)
# We'll pick a random index in the afternoon for the peak
peak_index = random.randint(80, 100) 

for i in range(POINTS):
    timestamp = start_time + (i * INTERVAL)
    
    # Base load simulation (diurnal cycle)
    hour = (timestamp % 86400) / 3600
    base_load = 500 + 400 * math.sin((hour - 6) * math.pi / 12)
    if base_load < 300: base_load = 300
    
    noise = random.uniform(-50, 50)
    value = base_load + noise
    
    # Inject specific peak
    if i == peak_index:
        # Sharp peak
        value = 4800.0 + random.uniform(0, 100)
        value = round(value, 2)
        peak_value = value
        peak_time = timestamp
    
    data_points.append([timestamp, value])

# 4. Insert Data
# Emoncms CSV import format: time,value per line, or JSON array
# For bulk insert, we can use feed/insert.json?data=[[t,v],[t,v]]
# We'll do it in chunks to be safe
chunk_size = 50
for i in range(0, len(data_points), chunk_size):
    chunk = data_points[i:i+chunk_size]
    data_str = json.dumps(chunk)
    api_call("feed/insert.json", {"id": feed_id, "data": data_str})

print(f"Data inserted. Peak: {peak_value} W at {peak_time}")

# 5. Save Ground Truth
ground_truth = {
    "feed_id": feed_id,
    "peak_watts": peak_value,
    "peak_timestamp": peak_time
}
with open("/tmp/ground_truth_peak.json", "w") as f:
    json.dump(ground_truth, f)

EOF

# Launch Firefox to the feed list
launch_firefox_to "http://localhost/feed/list" 5

# Remove any previous report file
rm -f /home/ga/peak_demand_report.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="