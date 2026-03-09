#!/bin/bash
# Setup script for Create Machine Status Indicator task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Machine Status Indicator Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is running
wait_for_emoncms

APIKEY=$(get_apikey_write)

# -----------------------------------------------------------------------
# 1. Clean previous state
# -----------------------------------------------------------------------
echo "Cleaning up previous data..."

# Delete dashboard if exists
DASH_ID=$(db_query "SELECT id FROM dashboard WHERE name='Factory Monitor' AND userid=1" 2>/dev/null | head -1)
if [ -n "$DASH_ID" ]; then
    curl -s "${EMONCMS_URL}/dashboard/delete?apikey=${APIKEY}&id=${DASH_ID}" >/dev/null 2>&1 || true
fi

# Delete feed if exists
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='press_running' AND userid=1" 2>/dev/null | head -1)
if [ -n "$FEED_ID" ]; then
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${FEED_ID}" >/dev/null 2>&1 || true
fi

# Clear input processes for 'press_power'
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='press_power' AND userid=1" 2>/dev/null | head -1)
if [ -n "$INPUT_ID" ]; then
    db_query "UPDATE input SET processList='' WHERE id=${INPUT_ID}"
else
    # Create input by posting first value
    curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=factory&fulljson={\"press_power\":25}" >/dev/null 2>&1 || true
    sleep 1
fi

# -----------------------------------------------------------------------
# 2. Start Background Data Generator
#    Simulates a machine cycle: Standby (25W) vs Active (1500W)
# -----------------------------------------------------------------------
cat > /tmp/machine_sim.py << 'PYEOF'
import time
import requests
import random
import sys
import math

apikey = sys.argv[1]
url = "http://localhost/input/post"

def post_power(watts):
    # Add some gaussian noise
    value = watts + random.gauss(0, watts * 0.05)
    try:
        requests.get(f"{url}?apikey={apikey}&node=factory&fulljson={{\"press_power\":{value:.2f}}}")
    except:
        pass

print("Starting machine simulation...")
cycle_time = 0
while True:
    # 60s cycle: 0-30s OFF, 30-60s ON
    state = (time.time() % 60) > 30
    
    if state:
        # Running
        post_power(1500)
    else:
        # Standby
        post_power(25)
        
    time.sleep(5)
PYEOF

# Kill any existing simulation
pkill -f "machine_sim.py" 2>/dev/null || true

# Start simulation in background
nohup python3 /tmp/machine_sim.py "$APIKEY" > /dev/null 2>&1 &
echo $! > /tmp/sim_pid.txt

# -----------------------------------------------------------------------
# 3. Prepare Browser
# -----------------------------------------------------------------------
# Navigate to Inputs page so agent sees the data coming in
launch_firefox_to "http://localhost/input/view" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="