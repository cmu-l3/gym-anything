#!/bin/bash
set -e
echo "=== Setting up Migrate Feed Interval Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# 1. Clean up any existing state (remove feed and input)
echo "Cleaning old state..."
APIKEY=$(get_apikey_write)
EXISTING_FEEDS=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" | jq -r '.[] | select(.name=="attic_temp") | .id')
for id in $EXISTING_FEEDS; do
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${id}" > /dev/null
done

# 2. Create the "Old" Feed (10s interval)
echo "Creating initial 10s feed..."
# Engine 5 = PHPFina, DataType 1 = Realtime
FEED_CREATE_RES=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=attic_temp&tag=attic&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=C")
FEED_ID=$(echo "$FEED_CREATE_RES" | jq -r '.feedid')

if [ -z "$FEED_ID" ] || [ "$FEED_ID" == "null" ]; then
    echo "ERROR: Failed to create initial feed"
    exit 1
fi
echo "Created feed ID: $FEED_ID"

# 3. Populate with dummy data (last 24 hours)
echo "Populating feed with data..."
python3 -c "
import urllib.request
import time
import math
import random

now = int(time.time())
feed_id = $FEED_ID
apikey = '$APIKEY'
base_url = '${EMONCMS_URL}'

# Generate 24 hours of data at 10s interval (~8640 points)
# We'll do a batch update CSV format for speed if possible, 
# or just a loop of post requests for simplicity in setup script context
# Actually, post.json accepts a CSV or JSON bulk update
data = []
start_time = now - (24 * 3600)
for t in range(start_time, now, 300): # Insert every 5 mins to save setup time, interpolation handles rest
    # Temp curve: colder at night, warmer in day
    hour = (t % 86400) / 3600
    temp = 15 + 10 * math.sin((hour - 6) * math.pi / 12) + random.uniform(-0.5, 0.5)
    # Emoncms bulk format: [time, nodeid, key, value] -- wait, feed/insert.json is simpler
    # /feed/insert.json?id=1&time=123&value=100
    
    # We will use input/post for bulk input then log to feed, but we need to bypass input for direct feed insertion
    # Direct feed insertion: /feed/insert.json
    try:
        url = f'{base_url}/feed/insert.json?apikey={apikey}&id={feed_id}&time={t}&value={temp:.2f}'
        urllib.request.urlopen(url)
    except:
        pass
print('Data population complete')
"

# 4. Create Input and Link to Feed
echo "Linking input to feed..."
# Post a value to create the input
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=attic&json={temp:20}" > /dev/null
sleep 1

# Get Input ID
INPUT_ID=$(db_query "SELECT id FROM input WHERE nodeid='attic' AND name='temp'" 2>/dev/null | head -1)

# Add 'Log to feed' process (Process ID 1)
# processList format: id:value,id:value (where id is process type, value is feed id)
# 1:FEED_ID
if [ -n "$INPUT_ID" ]; then
    # We use MySQL directly because the input/set_process API is complex to construct manually
    db_query "UPDATE input SET processList='1:${FEED_ID}' WHERE id=${INPUT_ID}"
    echo "Input ${INPUT_ID} linked to Feed ${FEED_ID}"
else
    echo "ERROR: Input not found"
fi

# Save initial Feed ID to verify it changes later
echo "$FEED_ID" > /tmp/initial_feed_id.txt

# 5. Launch Firefox
launch_firefox_to "${EMONCMS_URL}/feed/view" 5

# 6. Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="