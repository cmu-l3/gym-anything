#!/bin/bash
# setup_task.sh - Configure Water Monitoring Pipeline
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up task: configure_water_monitoring_pipeline ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is running
wait_for_emoncms

# -----------------------------------------------------------------------
# 1. Clean up any previous state (feeds or processes)
# -----------------------------------------------------------------------
echo "Cleaning previous state..."
APIKEY=$(get_apikey_write)

# Delete feeds if they exist
for feed in "water_total_m3" "water_flow_lpm"; do
    FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='$feed' AND userid=1" 2>/dev/null | head -1)
    if [ -n "$FEED_ID" ]; then
        curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${FEED_ID}" >/dev/null 2>&1 || true
        echo "Deleted old feed: $feed ($FEED_ID)"
    fi
done

# Clear input processes for node 10 (utility_room)
# Note: Input might not exist yet if fresh container, but try to clear if it does
INPUT_ID=$(db_query "SELECT id FROM input WHERE nodeid=10 AND name='main_water_pulses'" 2>/dev/null | head -1)
if [ -n "$INPUT_ID" ]; then
    db_query "UPDATE input SET processList='' WHERE id=${INPUT_ID}" 2>/dev/null || true
    echo "Cleared processes for existing input ($INPUT_ID)"
fi

# -----------------------------------------------------------------------
# 2. Simulate historical data to make input visible
# -----------------------------------------------------------------------
echo "Simulating initial water meter history..."

# We generate a short history so the input appears in the list
# Start at 15000 pulses
START_COUNT=15000
NOW=$(date +%s)
START_TIME=$((NOW - 3600)) # 1 hour ago

# Create a small python script to post history rapidly
cat > /tmp/simulate_history.py << PYTHON_EOF
import urllib.request
import urllib.parse
import time
import sys

apikey = "$APIKEY"
base_url = "http://localhost/input/post"
start_time = $START_TIME
start_count = $START_COUNT

# Post 10 data points spaced 10s apart
for i in range(10):
    timestamp = start_time + (i * 10)
    count = start_count + (i * 2) # Slow flow
    
    data = {"node": "utility_room", "json": f"{{main_water_pulses:{count}}}", "apikey": apikey, "time": timestamp}
    encoded = urllib.parse.urlencode(data)
    try:
        url = f"{base_url}?{encoded}"
        urllib.request.urlopen(url)
    except:
        pass
    time.sleep(0.1)

# Post one final 'current' point
current_data = {"node": "utility_room", "json": f"{{main_water_pulses:{start_count + 25}}}", "apikey": apikey}
try:
    urllib.request.urlopen(f"{base_url}?{urllib.parse.urlencode(current_data)}")
    print("Posted current data point")
except Exception as e:
    print(f"Error posting: {e}")
PYTHON_EOF

python3 /tmp/simulate_history.py

# -----------------------------------------------------------------------
# 3. Prepare Environment
# -----------------------------------------------------------------------

# Launch Firefox to the Inputs page
# Agent needs to see the input "main_water_pulses" under node "utility_room"
launch_firefox_to "http://localhost/input/view" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="