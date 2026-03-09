#!/bin/bash
set -e

echo "=== Setting up Battery Simulation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Install numpy for data generation if needed (usually standard, but ensuring)
# pip install numpy >/dev/null 2>&1 || true

# Generate realistic data and populate Emoncms
echo "Generating 7 days of 10-minute interval data..."

python3 -c "
import urllib.request
import urllib.parse
import json
import math
import random
import time
import sys

# Constants
APIKEY = '${EMONCMS_APIKEY_WRITE}'
BASE_URL = 'http://localhost'
FEED_NAME = 'surplus_power'
INTERVAL = 600  # 10 minutes
DAYS = 7
POINTS = int((DAYS * 24 * 3600) / INTERVAL)
NOW = int(time.time())
START_TIME = NOW - (POINTS * INTERVAL)

def api_call(endpoint, params):
    url = f'{BASE_URL}/{endpoint}'
    data = urllib.parse.urlencode(params).encode('utf-8')
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except Exception as e:
        print(f'Error calling {endpoint}: {e}')
        return None

# 1. Create Feed
print(f'Creating feed {FEED_NAME}...')
res = api_call('feed/create.json', {
    'apikey': APIKEY,
    'name': FEED_NAME,
    'tag': 'simulation',
    'datatype': 1,
    'engine': 5, # PHPFina
    'options': json.dumps({'interval': INTERVAL}),
    'unit': 'W'
})
feed_id = res.get('feedid')
if not feed_id:
    print('Failed to create feed')
    sys.exit(1)

print(f'Feed created with ID: {feed_id}')

# 2. Generate Data
# Pattern: Solar curve (day) - Consumption (constant + peaks)
print(f'Generating {POINTS} data points...')

def get_surplus(timestamp):
    # Hour of day (0-23.99)
    hour = (timestamp % 86400) / 3600
    
    # Solar generation (0 during night, peak at noon)
    solar = 0
    if 6 < hour < 18:
        # Sine wave for solar
        solar = 4000 * math.sin(math.pi * (hour - 6) / 12)
        # Add random cloud cover
        if random.random() > 0.8:
            solar *= random.uniform(0.2, 0.8)
    
    # Consumption (Base load + peaks in morning/evening)
    consumption = 300 + random.uniform(-50, 50)
    if 7 < hour < 9: # Morning peak
        consumption += 1500
    if 18 < hour < 22: # Evening peak
        consumption += 2000
    
    return solar - consumption

# 3. Post Data
# We will use direct calls. To speed up, we rely on Emoncms handling requests fast.
# Batching isn't natively supported easily without CSV upload, 
# so we'll do sequential requests but print progress.
# For 1000 points, this might take ~10-20 seconds.

print('Uploading data...')
for i in range(POINTS):
    ts = START_TIME + (i * INTERVAL)
    val = get_surplus(ts)
    
    # Post every point
    # feed/insert.json?id=1&time=123&value=100
    try:
        # We construct URL manually for GET to be faster/simpler or stick to POST
        # Using insert.json which is specific for historical data
        api_call('feed/insert.json', {
            'apikey': APIKEY,
            'id': feed_id,
            'time': ts,
            'value': round(val, 2)
        })
    except:
        pass
        
    if i % 100 == 0:
        print(f'Progress: {i}/{POINTS}', end='\r')

print(f'\nData upload complete for feed {feed_id}')
"

# Launch Firefox to Emoncms login
launch_firefox_to "http://localhost/" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Save start time for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="