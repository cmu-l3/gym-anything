#!/bin/bash
# Export script for derive_power_factor task

source /workspace/scripts/task_utils.sh

echo "=== Exporting results ==="

# 1. Stop simulation (to stabilize values for check)
pkill -f "simulate_motor.py" || true

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Fetch Data for Verification
APIKEY=$(get_apikey_read)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# A. Get Feed List
FEEDS_JSON=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}")
echo "$FEEDS_JSON" > /tmp/feeds_list.json

# B. Get Input List (contains processList strings)
INPUTS_JSON=$(curl -s "${EMONCMS_URL}/input/list.json?apikey=${APIKEY}")
echo "$INPUTS_JSON" > /tmp/inputs_list.json

# C. Get Value of motor_PF feed (if it exists)
# Extract ID using python for safety
FEED_ID=$(python3 -c "import json, sys; feeds=json.load(open('/tmp/feeds_list.json')); print(next((f['id'] for f in feeds if f['name']=='motor_PF'), ''))" 2>/dev/null)

FEED_VALUE="0"
FEED_UPDATED="0"
FEED_EXISTS="false"

if [ -n "$FEED_ID" ]; then
    FEED_EXISTS="true"
    # Get latest value
    FEED_VALUE=$(curl -s "${EMONCMS_URL}/feed/value.json?apikey=${APIKEY}&id=${FEED_ID}")
    # Get meta data for update time
    FEED_META=$(curl -s "${EMONCMS_URL}/feed/get.json?apikey=${APIKEY}&id=${FEED_ID}")
    FEED_UPDATED=$(echo "$FEED_META" | python3 -c "import json, sys; print(json.load(sys.stdin).get('time', 0))")
fi

# D. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "timestamp": $NOW,
    "feed_exists": $FEED_EXISTS,
    "feed_id": "$FEED_ID",
    "feed_value": "$FEED_VALUE",
    "feed_updated": $FEED_UPDATED,
    "feeds_list": $(cat /tmp/feeds_list.json),
    "inputs_list": $(cat /tmp/inputs_list.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json