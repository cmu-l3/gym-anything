#!/bin/bash
echo "=== Exporting Battery Simulation Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Agent Output File
AGENT_FILE="/home/ga/battery_simulation.json"
AGENT_FILE_EXISTS="false"
AGENT_VALUE="0"

if [ -f "$AGENT_FILE" ]; then
    AGENT_FILE_EXISTS="true"
    # Extract value using python to be safe against JSON formatting
    AGENT_VALUE=$(python3 -c "import json; print(json.load(open('$AGENT_FILE')).get('total_avoided_import_kwh', 0))" 2>/dev/null || echo "0")
fi

# 3. Calculate Ground Truth
# We run the EXACT simulation logic described in the task on the ACTUAL data in Emoncms
echo "Calculating ground truth..."

GROUND_TRUTH_JSON=$(python3 -c "
import urllib.request
import json
import sys

# Config
APIKEY = '${EMONCMS_APIKEY_READ}'
BASE_URL = 'http://localhost'
BATTERY_CAPACITY = 5.0 # kWh
FEED_NAME = 'surplus_power'

def get_feed_data():
    # 1. Get Feed ID
    try:
        list_url = f'{BASE_URL}/feed/list.json?apikey={APIKEY}'
        with urllib.request.urlopen(list_url) as resp:
            feeds = json.loads(resp.read().decode())
            feed_id = next((f['id'] for f in feeds if f['name'] == FEED_NAME), None)
            interval = next((f.get('interval', 600) for f in feeds if f['name'] == FEED_NAME), 600)
    except Exception as e:
        return None, None, str(e)

    if not feed_id:
        return None, None, 'Feed not found'

    # 2. Get Data
    # Fetch all data (start=0 means earliest, end=0 means latest usually, or use huge window)
    # Using specific window: now - 7 days
    # Actually, getting *all* data is safer to match agent's likely 'get all' approach
    # We'll use start=1 to avoid 0 issues
    try:
        data_url = f'{BASE_URL}/feed/data.json?apikey={APIKEY}&id={feed_id}&start=1&end=9999999999&interval={interval}'
        with urllib.request.urlopen(data_url) as resp:
            data = json.loads(resp.read().decode())
            return data, interval, None
    except Exception as e:
        return None, None, str(e)

def simulate(data, interval_sec):
    battery_kwh = 0.0
    avoided_import = 0.0
    
    # Emoncms data format: [timestamp, value]
    for point in data:
        power_w = point[1]
        if power_w is None: continue
        
        # Energy in this interval
        energy_kwh = power_w * (interval_sec / 3600.0) / 1000.0
        
        if energy_kwh > 0:
            # Surplus: Charge
            space = BATTERY_CAPACITY - battery_kwh
            charge = min(energy_kwh, space)
            battery_kwh += charge
        else:
            # Deficit: Discharge
            needed = -energy_kwh
            discharge = min(needed, battery_kwh)
            battery_kwh -= discharge
            avoided_import += discharge
            
    return avoided_import

data, interval, err = get_feed_data()
if err:
    print(json.dumps({'error': err}))
else:
    truth = simulate(data, interval)
    print(json.dumps({
        'ground_truth_kwh': truth,
        'data_points': len(data),
        'interval': interval
    }))
")

echo "Ground Truth Result: $GROUND_TRUTH_JSON"

# 4. Save results to JSON for Verifier
# We combine everything into a single JSON
python3 -c "
import json
import os

agent_exists = '$AGENT_FILE_EXISTS' == 'true'
agent_val = float('$AGENT_VALUE')

try:
    gt_data = json.loads('$GROUND_TRUTH_JSON')
    ground_truth = gt_data.get('ground_truth_kwh', 0)
    error_msg = gt_data.get('error')
except:
    ground_truth = 0
    error_msg = 'Failed to parse ground truth'

result = {
    'file_exists': agent_exists,
    'agent_value': agent_val,
    'ground_truth_value': ground_truth,
    'error_msg': error_msg,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="