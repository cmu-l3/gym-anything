#!/bin/bash
set -e
echo "=== Setting up Compute Heat Pump COP Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# API Setup
APIKEY_WRITE=$(get_apikey_write)
APIKEY_READ=$(get_apikey_read)
BASE_URL="http://localhost"

echo "Using Write API Key: $APIKEY_WRITE"

# ------------------------------------------------------------------
# Python script to generate realistic heat pump data and populate feeds
# ------------------------------------------------------------------
cat > /tmp/generate_hp_data.py << PYTHON_EOF
import urllib.request
import urllib.parse
import json
import math
import random
import time
import sys

# Configuration
APIKEY = "$APIKEY_WRITE"
BASE_URL = "$BASE_URL"
START_TIME = int(time.time()) - (24 * 3600)  # 24 hours ago
INTERVAL = 60
POINTS = 1440

def api_call(endpoint, params):
    params['apikey'] = APIKEY
    query = urllib.parse.urlencode(params)
    url = f"{BASE_URL}/{endpoint}?{query}"
    try:
        with urllib.request.urlopen(url) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        sys.stderr.write(f"Error calling {endpoint}: {e}\n")
        return None

# 1. Create Feeds
print("Creating feeds...")
feed_elec = api_call("feed/create.json", {"name": "heatpump_elec", "tag": "heatpump", "datatype": 1, "engine": 5, "options": json.dumps({"interval": INTERVAL}), "unit": "W"})
feed_heat = api_call("feed/create.json", {"name": "heatpump_heat", "tag": "heatpump", "datatype": 1, "engine": 5, "options": json.dumps({"interval": INTERVAL}), "unit": "W"})

if not feed_elec or not feed_heat:
    print("Failed to create feeds")
    sys.exit(1)

elec_id = feed_elec['feedid']
heat_id = feed_heat['feedid']
print(f"Feeds created: Elec ID={elec_id}, Heat ID={heat_id}")

# 2. Generate Data
# Simulation: Heat pump cycling on/off with varying COP based on outside temp proxy
random.seed(42) # Fixed seed for reproducibility
data_elec = []
data_heat = []
valid_cops = []

current_time = START_TIME
state_on = True
cycle_timer = 0

for i in range(POINTS):
    # Time of day (0-24)
    hour = (i / 60) % 24
    
    # Outside temp proxy (coldest at 4am, warmest at 3pm)
    temp_proxy = 5 + 10 * math.sin((hour - 4) * math.pi / 12)
    
    # Heat demand (higher when cold)
    demand = max(0, 20 - temp_proxy)
    
    # Cycle logic
    cycle_timer += 1
    if state_on and cycle_timer > 60: # Max run time
        state_on = False
        cycle_timer = 0
    elif not state_on and cycle_timer > 20 and demand > 5:
        state_on = True
        cycle_timer = 0
    
    # Calculate Power
    elec_w = 0
    heat_w = 0
    
    if state_on:
        # COP depends on temp (Carnot efficiency proxy)
        # Higher temp -> Higher COP
        base_cop = 2.5 + (temp_proxy * 0.1)
        # Add some noise
        cop = base_cop + random.uniform(-0.2, 0.2)
        
        elec_w = 800 + random.uniform(-50, 50) # Compressor power
        heat_w = elec_w * cop
        
        if elec_w >= 50:
            valid_cops.append(cop)
    else:
        # Standby
        elec_w = random.uniform(2, 5)
        heat_w = 0

    data_elec.append([current_time, round(elec_w, 2)])
    data_heat.append([current_time, round(heat_w, 2)])
    current_time += INTERVAL

# 3. Bulk Insert (chunked to avoid URL length limits)
print("Inserting data...")
def chunk_insert(feed_id, data_points):
    chunk_size = 100
    for i in range(0, len(data_points), chunk_size):
        chunk = data_points[i:i+chunk_size]
        # format: [[time,value],[time,value]...]
        json_data = json.dumps(chunk)
        # Emoncms 'post' endpoint often takes CSV or JSON. 
        # For historical data, feed/insert.json is usually point-by-point or requires specific formatting.
        # However, we can use the 'post.json' endpoint with a time offset if we are careful, 
        # OR just loop insert.json for reliability in this script (localhost is fast).
        
        # Using loop for reliability with feed/insert.json
        for pt in chunk:
            api_call("feed/insert.json", {"id": feed_id, "time": pt[0], "value": pt[1]})
        
        if i % 300 == 0:
            print(f"  Inserted {i} points for feed {feed_id}")

chunk_insert(elec_id, data_elec)
chunk_insert(heat_id, data_heat)

# 4. Save Ground Truth Stats
if valid_cops:
    stats = {
        "count": len(valid_cops),
        "avg": round(sum(valid_cops) / len(valid_cops), 2),
        "max": round(max(valid_cops), 2),
        "min": round(min(valid_cops), 2),
        "elec_id": elec_id,
        "heat_id": heat_id
    }
    with open('/var/lib/emoncms/cop_ground_truth.json', 'w') as f:
        json.dump(stats, f)
    print("Ground truth saved.")

PYTHON_EOF

# Execute the data generation script
python3 /tmp/generate_hp_data.py

# Clean up any pre-existing 'heatpump_cop' feed from previous runs
EXISTING_COP=$(db_query "SELECT id FROM feeds WHERE name='heatpump_cop'" 2>/dev/null | head -1)
if [ -n "$EXISTING_COP" ]; then
    echo "Removing stale heatpump_cop feed (ID: $EXISTING_COP)"
    curl -s "${BASE_URL}/feed/delete.json?apikey=${APIKEY_WRITE}&id=${EXISTING_COP}" > /dev/null
fi

# Set permissions for ground truth (hidden from agent, but readable by root/verifier)
chmod 644 /var/lib/emoncms/cop_ground_truth.json 2>/dev/null || true

# Prepare Firefox
launch_firefox_to "http://localhost/feed/list" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="