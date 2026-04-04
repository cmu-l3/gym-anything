#!/bin/bash
set -e
echo "=== Setting up Configure Multi-Res Logging Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Emoncms is ready
wait_for_emoncms

# 2. Get API Keys
APIKEY_WRITE=$(get_apikey_write)

# 3. Clean up any previous state (delete specific feeds if they exist)
echo "Cleaning up old feeds..."
EXISTING_IDS=$(db_query "SELECT id FROM feeds WHERE name IN ('rack_power_live', 'rack_power_archive') AND userid=1")
for id in $EXISTING_IDS; do
    if [ -n "$id" ]; then
        curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY_WRITE}&id=${id}" >/dev/null
        echo "Deleted old feed ID: $id"
    fi
done

# 4. Initialize the input 'rack_power_main' by posting data
# This creates the input if it doesn't exist
echo "Initializing input..."
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY_WRITE}&node=server_room&fulljson={\"rack_power_main\":550}" >/dev/null

# 5. Clear any existing process list on this input to ensure clean slate
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='rack_power_main' AND userid=1" | head -1)
if [ -n "$INPUT_ID" ]; then
    db_query "UPDATE input SET processList='' WHERE id=${INPUT_ID}"
    echo "Cleared process list for input ID: $INPUT_ID"
fi

# 6. Start a background data generator to make the input "live"
# This helps the agent see the input updating in real-time
cat > /tmp/input_generator.py << PYTHON_EOF
import time
import urllib.request
import random
import sys

apikey = "$APIKEY_WRITE"
url = "${EMONCMS_URL}/input/post"

print("Starting background data generator...")
while True:
    power = 550 + random.uniform(-50, 50)
    try:
        req_url = f"{url}?apikey={apikey}&node=server_room&fulljson={{\"rack_power_main\":{power:.2f}}}"
        with urllib.request.urlopen(req_url) as response:
            pass
    except Exception as e:
        print(f"Error posting data: {e}")
    time.sleep(10)
PYTHON_EOF

nohup python3 /tmp/input_generator.py > /tmp/generator.log 2>&1 &
echo $! > /tmp/generator_pid.txt

# 7. Launch Firefox to the Inputs page
# This puts the agent right where they need to be
launch_firefox_to "http://localhost/input/view" 5

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="