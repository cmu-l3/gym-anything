#!/bin/bash
set -e
echo "=== Setting up task: Correct Reversed Polarity ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the simulation script
#    This script posts negative values to Emoncms to simulate a reversed sensor
mkdir -p /workspace/tasks/correct_reversed_polarity
cat > /workspace/tasks/correct_reversed_polarity/simulate_reversed_sensor.py << 'EOF'
import sys
import time
import math
import random
import urllib.request
import urllib.parse
import datetime

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost"
APIKEY = sys.argv[2] if len(sys.argv) > 2 else ""
NODE_NAME = "garage_solar"
INTERVAL = 5

def post_data(node, data):
    try:
        json_str = "{" + ",".join(f'"{k}":{v}' for k, v in data.items()) + "}"
        params = {"node": node, "fulljson": json_str, "apikey": APIKEY}
        url = f"{BASE_URL}/input/post?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as resp:
            resp.read()
    except Exception:
        pass

def get_solar_value():
    # Generate a negative solar value (reversed polarity)
    # Use a fixed sine wave pattern regardless of actual time to ensure task consistency
    # Simulation time progresses by 10 mins every step to show movement if needed,
    # but for this task, just providing a non-zero negative value is sufficient.
    
    # Just return a negative value between -1000 and -3000 Watts
    val = random.uniform(1000, 3000)
    return -1 * round(val, 2)

print(f"Starting simulation for node {NODE_NAME}...")
while True:
    val = get_solar_value()
    post_data(NODE_NAME, {"power": val})
    time.sleep(INTERVAL)
EOF

# 2. Start the simulation in background
echo "Starting reversed sensor simulation..."
nohup python3 /workspace/tasks/correct_reversed_polarity/simulate_reversed_sensor.py \
    "http://localhost" "$(get_apikey_write)" > /tmp/sensor_sim.log 2>&1 &
echo $! > /tmp/sensor_sim.pid

# 3. Wait for data to appear in Emoncms
echo "Waiting for 'garage_solar' input to appear..."
APIKEY=$(get_apikey_read)
for i in {1..30}; do
    # Check via API if input exists
    RESP=$(curl -s "${EMONCMS_URL}/input/list.json?apikey=${APIKEY}")
    if echo "$RESP" | grep -q "garage_solar"; then
        echo "Input 'garage_solar' detected."
        break
    fi
    sleep 1
done

# 4. Launch Firefox to Inputs page
echo "Launching Firefox..."
launch_firefox_to "http://localhost/input/view" 5

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="