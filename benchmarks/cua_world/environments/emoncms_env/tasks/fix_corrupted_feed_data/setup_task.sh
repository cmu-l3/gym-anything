#!/bin/bash
# setup_task.sh — Fix Corrupted Solar Feed Data
# Creates a solar feed, populates it with realistic data, and injects 5 spikes.

source /workspace/scripts/task_utils.sh

echo "=== Setting up task: fix_corrupted_feed_data ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Emoncms to be ready
wait_for_emoncms

# Get the API key
APIKEY=$(get_apikey_write)
echo "Using API key: ${APIKEY}"

# 1. Ensure 'solar_gen' feed exists
# -----------------------------------------------------------------------
SOLAR_FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='solar_gen' LIMIT 1" | tr -d '[:space:]')

if [ -z "$SOLAR_FEED_ID" ]; then
    echo "Creating 'solar_gen' feed..."
    # Create feed via API
    # datatype=1 (Realtime), engine=5 (PHPFina), interval=10
    RESULT=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=solar_gen&tag=Solar&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W")
    SOLAR_FEED_ID=$(echo "$RESULT" | jq -r '.feedid')
    
    if [ "$SOLAR_FEED_ID" == "null" ] || [ -z "$SOLAR_FEED_ID" ]; then
        echo "Failed to create feed via API. Result: $RESULT"
        exit 1
    fi
    echo "Created feed ID: $SOLAR_FEED_ID"
fi

# 2. Populate with data and inject spikes
# -----------------------------------------------------------------------
echo "Generating solar data and injecting spikes..."

python3 << PYEOF
import json
import urllib.request
import urllib.parse
import time
import math
import random
import os

APIKEY = "${APIKEY}"
FEED_ID = ${SOLAR_FEED_ID}
BASE_URL = "${EMONCMS_URL}"
SPIKE_VALUE = 50000.0

def api_call(endpoint, params):
    url = f"{BASE_URL}/{endpoint}"
    query = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in params.items())
    full_url = f"{url}?{query}"
    try:
        with urllib.request.urlopen(full_url, timeout=10) as resp:
            return resp.read().decode('utf-8')
    except Exception as e:
        print(f"API Error: {e}")
        return None

# Generate 24 hours of 10s data (8640 points) ending now
now_ts = int(time.time())
start_ts = now_ts - 86400
interval = 10

print(f"Generating data from {start_ts} to {now_ts}...")

# Bulk data generation
# Emoncms PHPFina stores float values. We can post data point by point or use post.json
# For speed, we'll just generate the points and use a loop or batch if possible.
# Actually, generating 8640 points via HTTP GET one by one is slow.
# We will generate a CSV and use the bulk upload if available, or just use a loop with curl.
# For robustness in this environment, we will generate the binary file directly? No, that's unsafe.
# We will use the 'input/post' to create inputs, but here we are writing directly to a feed.
# The 'feed/insert.json' is the way.

# To be faster, we'll only generate interesting data (daytime) and 0 for night.
# Simulating a day: 6am to 8pm sun.
# Timestamps are UNIX seconds.

bulk_data = []
daytime_indices = []

# Generate a sine wave for solar
points_generated = 0
current_ts = start_ts
while current_ts <= now_ts:
    # Hour of day (local approx)
    hour = (current_ts % 86400) / 3600.0
    
    # Solar curve between 6 and 20
    val = 0
    if 6 <= hour <= 20:
        # Peak at 13:00 (13.0), width approx 7 hours sigma
        # Simple sine approximation
        # Normalized: (hour - 6) / 14 * pi
        x = (hour - 6) / 14.0 * math.pi
        if 0 <= x <= math.pi:
            base_solar = 3000 * math.sin(x)
            # Add some noise/clouds
            noise = random.uniform(0.9, 1.1)
            if random.random() > 0.8: noise *= 0.5 # Cloud
            val = base_solar * noise
    
    # Randomly keep indices for potential spikes if value > 100
    if val > 500:
        daytime_indices.append(current_ts)
        
    # We will insert points every 10 mins to establish baseline, 
    # and higher resolution around the spikes?
    # No, let's just do every 60 seconds to save setup time, the task says 10s interval feed
    # but doesn't require 10s resolution data for the whole day.
    
    # Optimization: Only insert data every minute
    if current_ts % 60 == 0:
        bulk_data.append((current_ts, val))
    
    current_ts += 60

# Insert baseline data (batching not supported easily on feed/insert, doing loop)
# To speed up, we only insert ~1440 points. Python urlopen is fast enough locally.
print(f"Inserting {len(bulk_data)} baseline data points...")
for ts, val in bulk_data:
    # Only insert if > 0 to save time, or every 10th zero
    if val > 0 or ts % 600 == 0:
        api_call("feed/insert.json", {"apikey": APIKEY, "id": FEED_ID, "time": ts, "value": val})

# Select 5 timestamps for spikes
if len(daytime_indices) < 5:
    print("Error: Not enough daytime points generated")
    exit(1)

random.seed(42)
spike_timestamps = sorted(random.sample(daytime_indices, 5))

spikes_meta = []
print("Injecting 5 spikes...")
for ts in spike_timestamps:
    # Inject spike
    api_call("feed/insert.json", {"apikey": APIKEY, "id": FEED_ID, "time": ts, "value": SPIKE_VALUE})
    
    # Record metadata
    spikes_meta.append({
        "timestamp": ts,
        "original_value": 0, # Don't care, we just want it fixed to < 4000
        "spike_value": SPIKE_VALUE
    })
    print(f"  Spike at {ts}: {SPIKE_VALUE} W")

# Save metadata for verification (HIDDEN)
meta = {
    "feed_id": FEED_ID,
    "spikes": spikes_meta
}
os.makedirs("/var/lib/emoncms_task", exist_ok=True)
with open("/var/lib/emoncms_task/spike_metadata.json", "w") as f:
    json.dump(meta, f)
    
print("Data setup complete.")
PYEOF

# 3. Setup Agent View
# -----------------------------------------------------------------------
# Launch Firefox to Feeds page
launch_firefox_to "http://localhost/feed/list" 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="