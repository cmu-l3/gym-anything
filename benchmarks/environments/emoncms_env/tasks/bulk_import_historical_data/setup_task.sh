#!/bin/bash
set -e
echo "=== Setting up bulk_import_historical_data task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Emoncms is ready
wait_for_emoncms

# 3. Clean up previous state (idempotency)
echo "Cleaning up any existing data..."
APIKEY=$(get_apikey_write)

# Delete feed 'annex_power' if exists
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='annex_power' AND userid=1" 2>/dev/null | head -1)
if [ -n "$FEED_ID" ]; then
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${FEED_ID}" >/dev/null
    echo "Deleted existing feed ID: $FEED_ID"
fi

# Delete input 'building_annex' if exists
# Note: Input deletion via API is input/delete?inputid=... or we can just clear the process list
# To fully delete the node, we usually just clear inputs.
# Let's check for the input ID
INPUT_ID=$(db_query "SELECT id FROM input WHERE nodeid='building_annex' AND name='power'" 2>/dev/null | head -1)
if [ -n "$INPUT_ID" ]; then
    curl -s "${EMONCMS_URL}/input/delete.json?apikey=${APIKEY}&inputid=${INPUT_ID}" >/dev/null
    echo "Deleted existing input ID: $INPUT_ID"
fi

# 4. Generate Historical Data CSV
echo "Generating historical data CSV..."
python3 -c "
import time
import math
import random

# Generate 144 points (24 hours * 6 per hour) ending 10 mins ago
end_time = int(time.time()) - 600
start_time = end_time - (144 * 600)

print('timestamp,power_watts')
for i in range(144):
    ts = start_time + (i * 600)
    
    # Calculate hour of day for pattern
    hour = (time.localtime(ts).tm_hour + time.localtime(ts).tm_min/60.0) % 24
    
    # Base load
    power = 300.0
    
    # Morning ramp (6-9)
    if 6 <= hour < 9:
        power += 1500 * (hour - 6) / 3
    # Day plateau (9-17)
    elif 9 <= hour < 17:
        power = 1800 + random.uniform(-200, 500)
    # Evening drop (17-22)
    elif 17 <= hour < 22:
        power = 1800 - 1300 * (hour - 17) / 5
    # Night
    else:
        power += random.uniform(-50, 50)
        
    print(f'{ts},{int(power)}')
" > /home/ga/annex_power_data.csv

chown ga:ga /home/ga/annex_power_data.csv
echo "Created /home/ga/annex_power_data.csv with 144 rows"

# 5. Launch Firefox to Input view
launch_firefox_to "http://localhost/input/view" 5

# 6. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="