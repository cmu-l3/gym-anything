#!/bin/bash
# Setup script for Aggregate Power Inputs task
set -e
echo "=== Setting up aggregate_power_inputs task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

APIKEY=$(get_apikey_write)
NOW=$(date +%s)

echo "--- Creating Inputs via API ---"
# Post data to create inputs: Node 'site_meters'
# Values: Main=3500, Annex=1200
curl -s "${EMONCMS_URL}/input/post?node=site_meters&fulljson={\"main_power\":3500,\"annex_power\":1200}&apikey=${APIKEY}&time=${NOW}" > /dev/null
sleep 2

# Get Input IDs
MAIN_INPUT_ID=$(db_query "SELECT id FROM inputs WHERE name='main_power' AND nodeid='site_meters'" | head -1)
ANNEX_INPUT_ID=$(db_query "SELECT id FROM inputs WHERE name='annex_power' AND nodeid='site_meters'" | head -1)

if [ -z "$MAIN_INPUT_ID" ] || [ -z "$ANNEX_INPUT_ID" ]; then
    echo "ERROR: Inputs creation failed"
    exit 1
fi

echo "Main Input ID: $MAIN_INPUT_ID"
echo "Annex Input ID: $ANNEX_INPUT_ID"

echo "--- Pre-configuring main_power ---"
# Create 'main_power_feed' if not exists
MAIN_FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='main_power_feed'" | head -1)
if [ -z "$MAIN_FEED_ID" ]; then
    # Create via API
    RESP=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=main_power_feed&tag=site_meters&datatype=1&engine=5&options={\"interval\":10}")
    MAIN_FEED_ID=$(echo "$RESP" | jq '.feedid')
fi

# Set main_power to log to its feed (Process 1: Log to feed)
# Format: 1:FEED_ID
if [ -n "$MAIN_FEED_ID" ] && [ "$MAIN_FEED_ID" != "null" ]; then
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e \
        "UPDATE inputs SET processList='1:${MAIN_FEED_ID}' WHERE id=${MAIN_INPUT_ID}"
    echo "Configured main_power (ID $MAIN_INPUT_ID) to log to feed $MAIN_FEED_ID"
fi

echo "--- Resetting annex_power ---"
# Clear process list for annex_power
docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e \
    "UPDATE inputs SET processList='' WHERE id=${ANNEX_INPUT_ID}"

# Remove target feeds if they exist (clean state)
EXISTING_ANNEX_FEED=$(db_query "SELECT id FROM feeds WHERE name='annex_power_feed'" | head -1)
if [ -n "$EXISTING_ANNEX_FEED" ]; then
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${EXISTING_ANNEX_FEED}" >/dev/null
    echo "Deleted stale annex_power_feed"
fi

EXISTING_TOTAL_FEED=$(db_query "SELECT id FROM feeds WHERE name='total_site_power'" | head -1)
if [ -n "$EXISTING_TOTAL_FEED" ]; then
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${EXISTING_TOTAL_FEED}" >/dev/null
    echo "Deleted stale total_site_power feed"
fi

# Launch Firefox to Inputs page
launch_firefox_to "http://localhost/input/view" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="