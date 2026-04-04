#!/bin/bash
# setup_task.sh — Prepare the export_feed_csv task

source /workspace/scripts/task_utils.sh

echo "=== Setting up export_feed_csv task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create export directory
mkdir -p /home/ga/exports
chown ga:ga /home/ga/exports

# Wait for Emoncms to be ready
wait_for_emoncms

APIKEY=$(get_apikey_write)
echo "Using API key: ${APIKEY}"

# -----------------------------------------------------------------------
# 1. Ensure "solar_pv" feed exists or create it
# -----------------------------------------------------------------------
echo "=== Checking/Creating solar_pv feed ==="

# Check if feed exists via API
EXISTING_FEED_ID=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    feeds = json.load(sys.stdin)
    for f in feeds:
        if f.get('name') == 'solar_pv':
            print(f['id'])
            break
except:
    pass
" 2>/dev/null || echo "")

if [ -z "$EXISTING_FEED_ID" ]; then
    echo "Creating solar_pv feed..."
    # Create PHPFina feed (engine=5), interval=10s
    CREATE_RESULT=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=solar_pv&tag=solar&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W" 2>/dev/null)
    FEED_ID=$(echo "$CREATE_RESULT" | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin)
    if r.get('success'):
        print(r.get('feedid', ''))
except:
    pass
" 2>/dev/null || echo "")
else
    FEED_ID="$EXISTING_FEED_ID"
    echo "Feed solar_pv already exists: ID=${FEED_ID}"
fi

# Fallback creation via DB if API fails
if [ -z "$FEED_ID" ]; then
    echo "Fallback: creating feed via MySQL"
    USERID=$(db_query "SELECT id FROM users WHERE username='admin' LIMIT 1" | head -1)
    db_query "INSERT INTO feeds (name, userid, tag, datatype, engine, unit, public) VALUES ('solar_pv', ${USERID:-1}, 'solar', 1, 5, 'W', 0)"
    FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='solar_pv' LIMIT 1" | head -1)
fi

echo "Target Feed ID: ${FEED_ID}"
echo "${FEED_ID}" > /tmp/solar_pv_feed_id.txt

# -----------------------------------------------------------------------
# 2. Populate feed with realistic solar data
# -----------------------------------------------------------------------
echo "=== Populating solar data ==="

# Clear existing data to ensure clean state (optional, but good for consistency)
# For PHPFina, clearing is hard without filesystem access, so we just append/overwrite recent data.

python3 - "${EMONCMS_URL}" "${APIKEY}" "${FEED_ID}" << 'PYEOF'
import urllib.request
import json
import math
import time
import random
import sys

BASE_URL = sys.argv[1]
APIKEY = sys.argv[2]
FEED_ID = sys.argv[3]

if not FEED_ID:
    sys.exit(0)

now = int(time.time())
# Generate 48 hours of data
start_time = now - (48 * 3600)
interval = 600 # 10 minutes

print(f"Generating data from {start_time} to {now}")

data_points = []
t = start_time
while t <= now:
    # Calculate hour of day (UTC) for solar curve
    hour = (t % 86400) / 3600.0
    
    # Solar curve (approximate)
    # Sunrise ~6am, Sunset ~8pm
    if 6.0 <= hour <= 20.0:
        # Peak at 13:00
        # Sine wave shape
        val = 3000 * math.sin(math.pi * (hour - 6.0) / 14.0)
        # Add random cloud cover (dip)
        if random.random() > 0.7:
            val *= random.uniform(0.2, 0.8)
        # Add noise
        val += random.uniform(-20, 20)
        val = max(0, val)
    else:
        val = 0.0
    
    # Emoncms bulk upload format: [time, value]
    # But for simplicity in script without CSV upload, use insert.json loop or simpler bulk
    # Using insert.json for simplicity in this script, though slower.
    # To speed up, we can use the data.json input if supported, or just loop fast.
    
    # Let's do batch inserts if possible? 
    # Emoncms 'post.json' with data=[[t,v],[t,v]...] is supported by some inputs, 
    # but for feeds directly we often use 'insert.json'.
    # We'll use a loop with short timeout.
    
    try:
        url = f"{BASE_URL}/feed/insert.json?apikey={APIKEY}&id={FEED_ID}&time={int(t)}&value={val:.2f}"
        urllib.request.urlopen(url, timeout=1).read()
    except:
        pass
        
    t += interval

print("Data population complete")
PYEOF

# -----------------------------------------------------------------------
# 3. Launch Firefox
# -----------------------------------------------------------------------
echo "=== Launching Firefox ==="
launch_firefox_to "http://localhost/feed/list" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== export_feed_csv setup complete ==="