#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: derive_residual_power ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Emoncms is ready
wait_for_emoncms

# 2. Create the Inputs and Initial Feeds via API
# We need to simulate the "Existing Configuration"
# Input: main_power -> Log to Feed (main_power)

echo "--- Configuring initial state ---"
APIKEY=$(get_apikey_write)

# Create Feeds first (to get IDs)
# main_power
main_feed_resp=$(emoncms_api "feed/create.json" "name=main_power&tag=home&datatype=1&engine=5")
MAIN_FEED_ID=$(echo "$main_feed_resp" | jq '.feedid')

# sub-circuit feeds (ev and hp usually logged too, let's create them for realism, 
# though the task only strictly requires using their *Inputs* for subtraction)
ev_feed_resp=$(emoncms_api "feed/create.json" "name=ev_charger&tag=home&datatype=1&engine=5")
EV_FEED_ID=$(echo "$ev_feed_resp" | jq '.feedid')

hp_feed_resp=$(emoncms_api "feed/create.json" "name=heat_pump&tag=home&datatype=1&engine=5")
HP_FEED_ID=$(echo "$hp_feed_resp" | jq '.feedid')

echo "Created feeds: Main=$MAIN_FEED_ID, EV=$EV_FEED_ID, HP=$HP_FEED_ID"

# Post initial data to create Inputs
# Node 'home' (nodeid usually numeric in DB, let's use 10)
emoncms_api "input/post" "node=10&fulljson={\"main_power\":3000,\"ev_charger\":1200,\"heat_pump\":800}" > /dev/null

# Get Input IDs
inputs_json=$(emoncms_api "input/list.json" "")
MAIN_INPUT_ID=$(echo "$inputs_json" | jq '.[] | select(.nodeid==10 and .name=="main_power") | .id')
EV_INPUT_ID=$(echo "$inputs_json" | jq '.[] | select(.nodeid==10 and .name=="ev_charger") | .id')
HP_INPUT_ID=$(echo "$inputs_json" | jq '.[] | select(.nodeid==10 and .name=="heat_pump") | .id')

echo "Created inputs: Main=$MAIN_INPUT_ID, EV=$EV_INPUT_ID, HP=$HP_INPUT_ID"

# Configure 'main_power' input processing: Just "Log to Feed" (Process ID 1)
# Format: processList=1:FEED_ID
emoncms_api "input/set_process.json" "inputid=$MAIN_INPUT_ID&processlist=1:$MAIN_FEED_ID"

# Configure EV and HP to log to their feeds too (standard setup)
emoncms_api "input/set_process.json" "inputid=$EV_INPUT_ID&processlist=1:$EV_FEED_ID"
emoncms_api "input/set_process.json" "inputid=$HP_INPUT_ID&processlist=1:$HP_FEED_ID"


# 3. Start Background Traffic Generator
# This script keeps the inputs "Live" with varying data so the agent sees values changing
cat > /tmp/traffic_gen.py << EOF
import time
import random
import urllib.request
import json
import sys

apikey = "$APIKEY"
base_url = "http://localhost/input/post"

def post_data():
    # Simulate realistic load
    # Residual (Base) varies around 400-600W
    base = random.uniform(400, 600)
    
    # EV is either 0 or 7000 (charging) or 1200 (trickle). Let's say steady 1200 for consistency
    ev = 1200 + random.uniform(-10, 10)
    
    # HP is cycling. Say 800W
    hp = 800 + random.uniform(-20, 20)
    
    # Main is the sum
    main = base + ev + hp
    
    json_data = json.dumps({
        "main_power": round(main, 2),
        "ev_charger": round(ev, 2),
        "heat_pump": round(hp, 2)
    })
    
    url = f"{base_url}?node=10&fulljson={json_data}&apikey={apikey}"
    try:
        urllib.request.urlopen(url)
    except:
        pass

print("Starting traffic generator...")
while True:
    post_data()
    time.sleep(5)
EOF

nohup python3 /tmp/traffic_gen.py > /tmp/traffic_gen.log 2>&1 &
echo $! > /tmp/traffic_gen.pid

# 4. Launch Browser
launch_firefox_to "http://localhost/input/view"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="