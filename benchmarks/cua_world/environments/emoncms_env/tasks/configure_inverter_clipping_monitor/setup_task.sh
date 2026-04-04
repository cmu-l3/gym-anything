#!/bin/bash
echo "=== Setting up Configure Inverter Clipping Monitor Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

APIKEY=$(get_apikey_write)

# 1. Clean up existing data to ensure fresh start
# Delete feeds if they exist
for feed in "solar_raw_W" "solar_excess_W" "solar_lost_kwh"; do
    EXISTING_ID=$(db_query "SELECT id FROM feeds WHERE name='$feed' AND userid=1" 2>/dev/null | head -1)
    if [ -n "$EXISTING_ID" ]; then
        curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${EXISTING_ID}" >/dev/null 2>&1 || true
        echo "Deleted existing feed: $feed (id=$EXISTING_ID)"
    fi
done

# 2. Setup the input
# We need to ensure the 'solar_pv' input exists on 'home' node.
# We do this by posting a value.
echo "Creating/Resetting 'solar_pv' input..."
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=home&fulljson={\"solar_pv\":2500}" >/dev/null

# Get Input ID
INPUT_ID=$(db_query "SELECT id FROM input WHERE nodeid='home' AND name='solar_pv'" 2>/dev/null | head -1)

# Clear any existing processes on this input
if [ -n "$INPUT_ID" ]; then
    db_query "UPDATE input SET processList='' WHERE id=$INPUT_ID"
    echo "Cleared process list for input id=$INPUT_ID"
else
    echo "ERROR: Failed to create input solar_pv"
    exit 1
fi

# 3. Launch Firefox to the Inputs page
# We send the user directly to the input view where they can start the task
launch_firefox_to "http://localhost/input/view" 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="