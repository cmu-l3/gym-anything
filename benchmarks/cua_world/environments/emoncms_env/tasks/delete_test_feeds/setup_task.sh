#!/bin/bash
# setup_task.sh — Set up the delete_test_feeds task
# NOTE: Do NOT use set -e (pattern #25 from task_utils)

source /workspace/scripts/task_utils.sh

echo "=== Setting up delete_test_feeds task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Emoncms
wait_for_emoncms

# Get the API key
APIKEY=$(get_apikey_write)
echo "Using API key: ${APIKEY}"

# -----------------------------------------------------------------------
# 1. Create the 4 test feeds via API
# -----------------------------------------------------------------------
echo "=== Creating test feeds ==="

TEST_FEEDS=("test_voltage_check" "test_ct_sensor_1" "test_calibration_run" "test_mqtt_connection")
TEST_UNITS=("V" "W" "W" "W")

for i in "${!TEST_FEEDS[@]}"; do
    FEED_NAME="${TEST_FEEDS[$i]}"
    FEED_UNIT="${TEST_UNITS[$i]}"

    # Check if feed already exists
    EXISTS=$(db_query "SELECT COUNT(*) FROM feeds WHERE name='${FEED_NAME}'" | head -1)
    if [ "${EXISTS}" = "0" ] || [ -z "${EXISTS}" ]; then
        # Create feed
        # We use a direct curl here to ensure it's created fresh
        RESULT=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=${FEED_NAME}&tag=test&datatype=1&engine=5&options={\"interval\":10}&unit=${FEED_UNIT}")
        echo "Created feed '${FEED_NAME}': ${RESULT}"
    else
        echo "Feed '${FEED_NAME}' already exists, skipping creation"
    fi
    sleep 0.5
done

# -----------------------------------------------------------------------
# 2. Record initial state for verification
# -----------------------------------------------------------------------
echo "=== Recording initial state ==="

# Total feed count
INITIAL_COUNT=$(db_query "SELECT COUNT(*) FROM feeds" | head -1)
echo "${INITIAL_COUNT}" > /tmp/initial_feed_count.txt
echo "Initial feed count: ${INITIAL_COUNT}"

# Record production (non-test) feed IDs to ensure they are NOT deleted
# We explicitly exclude the 4 test feeds we just ensured exist
db_query "SELECT id FROM feeds WHERE name NOT IN ('test_voltage_check','test_ct_sensor_1','test_calibration_run','test_mqtt_connection') ORDER BY id" > /tmp/production_feed_ids.txt
echo "Production feed IDs saved to /tmp/production_feed_ids.txt"

# -----------------------------------------------------------------------
# 3. Launch Firefox to the Feeds page
# -----------------------------------------------------------------------
echo "=== Launching Firefox to Feeds page ==="
launch_firefox_to "http://localhost/feed/list" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved"

echo "=== Task setup complete ==="