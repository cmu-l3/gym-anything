#!/bin/bash
# Export script for Configure Parasitic Load Filter task
# Performs functional "Black Box" testing of the agent's configuration

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot of the configuration
take_screenshot /tmp/task_final.png

APIKEY=$(get_apikey_write)
FEED_NAME="workshop_production_load"
INPUT_NAME="workshop_power"
NODE_NAME="workshop"

# 2. Check if the feed exists
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='${FEED_NAME}' AND userid=1" 2>/dev/null | head -1)

FEED_EXISTS="false"
if [ -n "$FEED_ID" ]; then
    FEED_EXISTS="true"
    echo "Found target feed ID: ${FEED_ID}"
else
    echo "Target feed '${FEED_NAME}' not found."
fi

# 3. FUNCTIONAL TEST A: LOW VALUE (Input 40 -> Expect 0)
# Logic: 40 - 45 = -5. 'Allow Positive' should clamp this to 0.
TEST_A_INPUT=40
TEST_A_EXPECT=0
TEST_A_RESULT="null"

echo "Running Test A: Input ${TEST_A_INPUT}..."
# Post data
curl -s "${EMONCMS_URL}/input/post?node=${NODE_NAME}&json={${INPUT_NAME}:${TEST_A_INPUT}}&apikey=${APIKEY}" > /dev/null
# Wait for processing (feed update)
sleep 2
# Read feed value
if [ -n "$FEED_ID" ]; then
    TEST_A_RESULT=$(curl -s "${EMONCMS_URL}/feed/value.json?apikey=${APIKEY}&id=${FEED_ID}" | tr -d '"')
fi
echo "Test A Result: ${TEST_A_RESULT} (Expected: ${TEST_A_EXPECT})"


# 4. FUNCTIONAL TEST B: HIGH VALUE (Input 145 -> Expect 100)
# Logic: 145 - 45 = 100.
TEST_B_INPUT=145
TEST_B_EXPECT=100
TEST_B_RESULT="null"

echo "Running Test B: Input ${TEST_B_INPUT}..."
# Post data
curl -s "${EMONCMS_URL}/input/post?node=${NODE_NAME}&json={${INPUT_NAME}:${TEST_B_INPUT}}&apikey=${APIKEY}" > /dev/null
# Wait for processing
sleep 2
# Read feed value
if [ -n "$FEED_ID" ]; then
    TEST_B_RESULT=$(curl -s "${EMONCMS_URL}/feed/value.json?apikey=${APIKEY}&id=${FEED_ID}" | tr -d '"')
fi
echo "Test B Result: ${TEST_B_RESULT} (Expected: ${TEST_B_EXPECT})"


# 5. Capture Process List Configuration (for debugging/verification)
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='${INPUT_NAME}'" 2>/dev/null | head -1)
PROCESS_LIST=""
if [ -n "$INPUT_ID" ]; then
    # Raw process list string from DB
    PROCESS_LIST=$(db_query "SELECT processList FROM input WHERE id=${INPUT_ID}" 2>/dev/null)
fi

# 6. Check if Firefox is running (was the agent actually using the tool?)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "feed_exists": ${FEED_EXISTS},
    "feed_id": "${FEED_ID}",
    "test_a": {
        "input": ${TEST_A_INPUT},
        "expected": ${TEST_A_EXPECT},
        "actual": "${TEST_A_RESULT}"
    },
    "test_b": {
        "input": ${TEST_B_INPUT},
        "expected": ${TEST_B_EXPECT},
        "actual": "${TEST_B_RESULT}"
    },
    "process_list_raw": "${PROCESS_LIST}",
    "app_was_running": ${APP_RUNNING},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export Complete ==="