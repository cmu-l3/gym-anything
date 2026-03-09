#!/bin/bash
set -e
echo "=== Setting up monitor_carbon_footprint task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is running
wait_for_emoncms

# Get API Keys
APIKEY_WRITE=$(get_apikey_write)

# 1. Clean up previous run artifacts (Feeds, Inputs, Dashboards)
# Delete dashboard if exists
DASH_ID=$(db_query "SELECT id FROM dashboard WHERE name='Sustainability_Display' AND userid=1" 2>/dev/null | head -1)
if [ -n "$DASH_ID" ]; then
    curl -s "${EMONCMS_URL}/dashboard/delete?apikey=${APIKEY_WRITE}&id=${DASH_ID}" >/dev/null
    echo "Cleaned up old dashboard"
fi

# Delete feed if exists
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='current_carbon_intensity' AND userid=1" 2>/dev/null | head -1)
if [ -n "$FEED_ID" ]; then
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY_WRITE}&id=${FEED_ID}" >/dev/null
    echo "Cleaned up old feed"
fi

# Delete input if exists to reset processing list
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='facility_main_power' AND nodeid='main_meter'" 2>/dev/null | head -1)
if [ -n "$INPUT_ID" ]; then
    curl -s "${EMONCMS_URL}/input/delete.json?apikey=${APIKEY_WRITE}&inputid=${INPUT_ID}" >/dev/null
    echo "Cleaned up old input"
fi

# 2. Create the specific input by posting data
echo "Creating input 'facility_main_power'..."
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY_WRITE}&node=main_meter&json={facility_main_power:2500}" >/dev/null
sleep 2

# 3. Start background data generator
# This ensures the input 'facility_main_power' keeps updating so the user sees live data
cat > /tmp/carbon_data_gen.py << PYTHON_EOF
import time
import random
import requests
import sys

apikey = "$APIKEY_WRITE"
url = "${EMONCMS_URL}/input/post"

print("Starting background data generator...")
while True:
    # Simulate facility power varying between 2000W and 5000W
    power = 2000 + random.uniform(0, 3000)
    try:
        requests.get(url, params={
            'apikey': apikey,
            'node': 'main_meter',
            'json': f'{{facility_main_power:{power:.2f}}}'
        }, timeout=5)
    except Exception as e:
        print(f"Error posting data: {e}")
    time.sleep(5)
PYTHON_EOF

# Run generator in background
nohup python3 /tmp/carbon_data_gen.py > /tmp/data_gen.log 2>&1 &
echo $! > /tmp/data_gen_pid.txt
echo "Background data generator started (PID $(cat /tmp/data_gen_pid.txt))"

# 4. Launch Firefox to the Inputs page
launch_firefox_to "${EMONCMS_URL}/input/view" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="