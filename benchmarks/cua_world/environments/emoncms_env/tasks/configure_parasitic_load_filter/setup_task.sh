#!/bin/bash
# Setup script for Configure Parasitic Load Filter task

echo "=== Setting up Configure Parasitic Load Filter Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Emoncms to be ready
wait_for_emoncms

# 2. Get API keys
APIKEY_WRITE=$(get_apikey_write)
echo "Using Write API Key: $APIKEY_WRITE"

# 3. Create/Reset the 'workshop_power' input
# Post a value to ensure input exists
echo "Creating/Resetting 'workshop_power' input..."
curl -s "${EMONCMS_URL}/input/post?node=workshop&json={workshop_power:150}&apikey=${APIKEY_WRITE}" > /dev/null

# Get the input ID
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='workshop_power' AND userid=1" 2>/dev/null | head -1)

if [ -n "$INPUT_ID" ]; then
    # Clear any existing process list (start clean)
    db_query "UPDATE input SET processList=NULL WHERE id=${INPUT_ID}"
    echo "Cleared process list for input ID ${INPUT_ID}"
else
    echo "ERROR: Failed to create workshop_power input"
    exit 1
fi

# 4. Remove the target feed if it exists (to prevent stale state)
FEED_NAME="workshop_production_load"
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='${FEED_NAME}' AND userid=1" 2>/dev/null | head -1)

if [ -n "$FEED_ID" ]; then
    echo "Removing existing feed '${FEED_NAME}' (ID: ${FEED_ID})..."
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY_WRITE}&id=${FEED_ID}" > /dev/null
    # Double check DB deletion
    db_query "DELETE FROM feeds WHERE id=${FEED_ID}"
fi

# 5. Launch Firefox to the Inputs page
echo "Launching Firefox..."
launch_firefox_to "${EMONCMS_URL}/input/view" 5

# 6. Record start time
date +%s > /tmp/task_start_time.txt

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="