#!/bin/bash
set -e
echo "=== Setting up Analyze Voltage Quality task ==="

# Source helper functions
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# Create directory for ground truth (hidden from standard user view)
mkdir -p /var/lib/emoncms/ground_truth
chmod 755 /var/lib/emoncms/ground_truth

# Get API Key
APIKEY=$(get_apikey_write)

# Generate Data Script
# This script creates the feed, generates 24h of data with specific faults, 
# and saves the ground truth analysis to a file.
cat > /tmp/generate_voltage_data.py << PYTHON_EOF
import time
import math
import random
import json
import urllib.request
import urllib.parse
import sys

APIKEY = "$APIKEY"
BASE_URL = "http://localhost"
FEED_NAME = "grid_voltage"
TAG = "mains"
NOW = int(time.time())
START_TIME = NOW - (24 * 3600)
INTERVAL = 10  # 10 seconds

def api_call(endpoint, params, post_data=None):
    url = f"{BASE_URL}/{endpoint}"
    if params:
        query = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in params.items())
        url = f"{url}?{query}"
    
    req = urllib.request.Request(url)
    if post_data:
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        req.data = urllib.parse.urlencode(post_data).encode('utf-8')
        
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        print(f"API Error: {e}")
        return None

# 1. Clean up existing feed if any
feeds = api_call("feed/list.json", {"apikey": APIKEY})
if feeds:
    for f in feeds:
        if f['name'] == FEED_NAME:
            api_call("feed/delete.json", {"apikey": APIKEY, "id": f['id']})
            print(f"Deleted old feed {f['id']}")

# 2. Create Feed
print(f"Creating feed {FEED_NAME}...")
res = api_call("feed/create.json", {
    "apikey": APIKEY, "name": FEED_NAME, "tag": TAG, 
    "datatype": 1, "engine": 5, "options": json.dumps({"interval": INTERVAL}), "unit": "V"
})
if not res or not res.get("success"):
    print("Failed to create feed")
    sys.exit(1)

feed_id = res.get("feedid")
print(f"Feed ID: {feed_id}")

# 3. Generate Data
# Pattern: Base 238V + Solar Rise (Sine) + Noise + Spikes
data_points = []
samples_over_253 = 0
max_v = 0.0

print("Generating 24 hours of data...")
for t in range(START_TIME, NOW, INTERVAL):
    # Time of day in hours (0-24)
    hour = (time.gmtime(t).tm_hour + time.gmtime(t).tm_min/60.0)
    
    # Base voltage
    val = 238.0
    
    # Solar rise effect (10am to 4pm)
    if 10 <= hour <= 16:
        # Peak at 13:00
        solar_impact = 12.0 * math.sin(math.pi * (hour - 10) / 6)
        val += solar_impact
        
    # Random noise
    val += random.uniform(-1.5, 1.5)
    
    # INJECT FAULTS (Over-voltage events)
    # Event 1: 11:15 - 11:30 (15 mins) -> +6V surge
    if 11.25 <= hour < 11.5:
        val += 6.0
        
    # Event 2: 13:45 - 13:50 (5 mins) -> +5V (pushing the solar peak over edge)
    if 13.75 <= hour < 13.833:
        val += 5.0

    # Round to 2 decimals like a real sensor
    val = round(val, 2)
    
    # Track stats for Ground Truth
    if val > 253.0:
        samples_over_253 += 1
    if val > max_v:
        max_v = val

    data_points.append([t, val])

# 4. Batch Insert
# API format for feed/insert.json?data=[[time,val],...]
chunk_size = 800
for i in range(0, len(data_points), chunk_size):
    chunk = data_points[i:i+chunk_size]
    # The data parameter must be a JSON string
    api_call("feed/insert.json", {"apikey": APIKEY, "id": feed_id}, {"data": json.dumps(chunk)})

# 5. Save Ground Truth
gt = {
    "feed_id": feed_id,
    "total_samples": len(data_points),
    "samples_over_253": samples_over_253,
    "minutes_over_253": round(samples_over_253 * INTERVAL / 60.0, 2),
    "max_voltage": max_v
}
with open("/var/lib/emoncms/ground_truth/voltage_truth.json", "w") as f:
    json.dump(gt, f)

print(f"Data generation complete. Truth: {gt}")
PYTHON_EOF

# Run the generation script
python3 /tmp/generate_voltage_data.py

# Launch Firefox to the feed view so the agent sees the feed immediately
launch_firefox_to "http://localhost/feed/view" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="