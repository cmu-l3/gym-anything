#!/bin/bash
set -e
echo "=== Setting up Detect Freezer Gaps task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is up
wait_for_emoncms

# Create directory for hidden ground truth (root only)
mkdir -p /var/lib/app/ground_truth
chmod 700 /var/lib/app/ground_truth

echo "Generating historical data with gaps..."

# Python script to generate data and setup feed
# This runs as root to ensure ground truth is protected, but interacts with API
python3 -c "
import urllib.request
import urllib.parse
import json
import time
import random
import sys

# API Configuration
BASE_URL = 'http://localhost'
# Read API key from file
try:
    with open('/home/ga/emoncms_apikeys.sh') as f:
        content = f.read()
        apikey = None
        for line in content.splitlines():
            if 'EMONCMS_APIKEY_WRITE' in line:
                apikey = line.split('=')[1].strip('\"')
                break
    if not apikey: raise Exception('API Key not found')
except Exception as e:
    print(f'Error reading API key: {e}')
    sys.exit(1)

def api_call(endpoint, params=None, data=None):
    params = params or {}
    params['apikey'] = apikey
    url = f'{BASE_URL}/{endpoint}'
    if params:
        url += '?' + urllib.parse.urlencode(params)
    
    req = urllib.request.Request(url)
    if data:
        req.data = data
    
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f'API error {endpoint}: {e}')
        return None

# 1. Cleanup old feed/input if exists
print('Cleaning up old data...')
feeds = api_call('feed/list.json')
if feeds:
    for f in feeds:
        if f['name'] == 'Freezer_Temp':
            api_call('feed/delete.json', {'id': f['id']})

inputs = api_call('input/list.json')
if inputs:
    for i in inputs:
        if i['nodeid'] == 'freezer':
            api_call('input/delete.json', {'inputid': i['id']})

# 2. Create Input and Feed via API simulation
# We post one value to create the input
print('Creating input...')
api_call('input/post.json', {'node': 'freezer', 'json': json.dumps({'temp': -20.0})})

# Get Input ID
inputs = api_call('input/list.json')
input_id = next((i['id'] for i in inputs if i['nodeid'] == 'freezer' and i['name'] == 'temp'), None)
if not input_id:
    print('Failed to create input')
    sys.exit(1)

# Create Feed
print('Creating feed...')
res = api_call('feed/create.json', {
    'name': 'Freezer_Temp', 
    'tag': 'ColdStorage', 
    'datatype': 1, 
    'engine': 5, # PHPFina
    'options': json.dumps({'interval': 10}),
    'unit': 'C'
})
feed_id = res['feedid']

# Add 'Log to Feed' process
print(f'Linking input {input_id} to feed {feed_id}...')
api_call('input/process/add.json', {
    'inputid': input_id,
    'processid': 1, # Log to feed
    'arg': feed_id,
    'newfeed': 0
})

# 3. Generate Data with Gap
now = int(time.time())
start_time = now - (24 * 3600)

# Define Gap: Random start between 20h ago and 4h ago
# Random duration between 30 min (1800s) and 90 min (5400s)
gap_duration = random.randint(1800, 5400)
gap_start_offset = random.randint(4 * 3600, 20 * 3600)
gap_start = now - gap_start_offset
gap_end = gap_start + gap_duration

print(f'Generating data from {start_time} to {now}')
print(f'Injected Gap: Start={gap_start} ({time.ctime(gap_start)}), Duration={gap_duration}s')

# Save Ground Truth (Hidden)
ground_truth = {
    'feed_id': feed_id,
    'gap_start_timestamp': gap_start,
    'gap_duration_seconds': gap_duration,
    'gap_end_timestamp': gap_end,
    'readable_start': time.ctime(gap_start),
    'readable_duration': f'{gap_duration/60:.1f} minutes'
}
with open('/var/lib/app/ground_truth/gap_info.json', 'w') as f:
    json.dump(ground_truth, f)

# Batch Data Generation
# We use input/bulk.json: data=[[time,node,key,value],...]
batch_size = 500
batch = []
current_time = start_time

while current_time < now:
    # Check if we are inside the gap
    if not (gap_start < current_time < gap_end):
        # Generate value: -20C base, slight sine wave + noise
        hour = (current_time % 86400) / 3600
        val = -20.0 + (0.5 * (hour % 2)) + random.uniform(-0.2, 0.2)
        
        # Add to batch
        batch.append([current_time, 'freezer', 'temp', round(val, 2)])
    
    if len(batch) >= batch_size:
        # Post batch
        data_str = json.dumps(batch)
        api_call('input/bulk.json', {'data': data_str})
        batch = []
        # Slight delay to not overwhelm if on low resources
        time.sleep(0.05)
        
    current_time += 10 # 10s interval

# Post remaining
if batch:
    api_call('input/bulk.json', {'data': json.dumps(batch)})

print('Data generation complete.')
"

# Launch Firefox to the Feed List page to start
launch_firefox_to "http://localhost/feed/list" 5

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="