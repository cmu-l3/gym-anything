#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Stop the background simulator to prevent interference during verification
if [ -f /tmp/generator_sim.pid ]; then
    kill $(cat /tmp/generator_sim.pid) 2>/dev/null || true
    echo "Simulator stopped."
fi

# 3. Verify Feed Existence
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='generator_hours'" 2>/dev/null | head -1)
FEED_EXISTS="false"
FEED_ENGINE=""
FEED_INTERVAL=""

if [ -n "$FEED_ID" ]; then
    FEED_EXISTS="true"
    FEED_ENGINE=$(db_query "SELECT engine FROM feeds WHERE id=$FEED_ID" 2>/dev/null)
    FEED_INTERVAL=$(db_query "SELECT split(options, '\"interval\":', 1) FROM feeds WHERE id=$FEED_ID" 2>/dev/null) # Simple parsing attempt, logic below is better
    # Use API for cleaner metadata if DB parse is messy
    FEED_META=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=$(get_apikey_read)" | jq ".[] | select(.id==$FEED_ID)")
    if [ -n "$FEED_META" ]; then
        FEED_ENGINE=$(echo "$FEED_META" | jq -r '.engine')
        FEED_INTERVAL=$(echo "$FEED_META" | jq -r '.interval')
    fi
fi

# 4. Verify Process List (Configuration Check)
# We need to see if the user added Scaling (x) and Integrator (Power to kWh)
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='generator_status'" 2>/dev/null | head -1)
PROCESS_LIST_JSON="[]"
HAS_SCALE="false"
HAS_INTEGRATOR="false"
SCALE_VALUE="0"

if [ -n "$INPUT_ID" ]; then
    # Fetch process list from DB
    # format: processid, arguments
    # 2 = scale/multiply, 5 = power_to_kwh (IDs may vary by version, checking names if possible via API)
    # Emoncms API returns process list with names
    PROCESS_LIST_JSON=$(curl -s "${EMONCMS_URL}/input/process/list.json?inputid=$INPUT_ID&apikey=$(get_apikey_read)")
    
    # Check for Scale (process id 2 usually, or name 'scale')
    SCALE_ENTRY=$(echo "$PROCESS_LIST_JSON" | jq '.[] | select(.process__name=="scale" or .process__name=="x")')
    if [ -n "$SCALE_ENTRY" ]; then
        HAS_SCALE="true"
        SCALE_VALUE=$(echo "$SCALE_ENTRY" | jq -r '.arguments_value // .value')
    fi
    
    # Check for Integrator
    INTEGRATOR_ENTRY=$(echo "$PROCESS_LIST_JSON" | jq '.[] | select(.process__name=="power_to_kwh")')
    if [ -n "$INTEGRATOR_ENTRY" ]; then
        HAS_INTEGRATOR="true"
    fi
fi

# 5. Functional Test: Measure Slope (Data Check)
# We will inject known data and measure the feed increment
SLOPE_DELTA="0"
if [ "$FEED_EXISTS" = "true" ]; then
    echo "Running slope test..."
    APIKEY_WRITE=$(get_apikey_write)
    
    # Get current value
    VAL1=$(curl -s "${EMONCMS_URL}/feed/value.json?apikey=$APIKEY_WRITE&id=$FEED_ID")
    
    # Post '1' (Running)
    curl -s "${EMONCMS_URL}/input/post?node=generator_room&json={generator_status:1}&apikey=$APIKEY_WRITE" > /dev/null
    
    # Wait 10 seconds
    sleep 10
    
    # Post '1' again to trigger processing of the interval
    curl -s "${EMONCMS_URL}/input/post?node=generator_room&json={generator_status:1}&apikey=$APIKEY_WRITE" > /dev/null
    
    # Wait small buffer for write
    sleep 1
    
    # Get new value
    VAL2=$(curl -s "${EMONCMS_URL}/feed/value.json?apikey=$APIKEY_WRITE&id=$FEED_ID")
    
    # Calculate delta using python
    SLOPE_DELTA=$(python3 -c "print(float($VAL2) - float($VAL1))" 2>/dev/null || echo "0")
    echo "Slope Test: Start=$VAL1, End=$VAL2, Delta=$SLOPE_DELTA"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "feed_exists": $FEED_EXISTS,
    "feed_id": "${FEED_ID:-0}",
    "feed_engine": "${FEED_ENGINE:-0}",
    "feed_interval": "${FEED_INTERVAL:-0}",
    "process_has_scale": $HAS_SCALE,
    "process_scale_value": "$SCALE_VALUE",
    "process_has_integrator": $HAS_INTEGRATOR,
    "functional_slope_delta": $SLOPE_DELTA,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="