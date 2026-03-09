#!/bin/bash
# setup_task.sh for configure_sensor_node_api@1

source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_sensor_node_api task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is running
wait_for_emoncms

# Verify API keys file exists (created by env setup, but good to check)
if [ ! -f /home/ga/emoncms_apikeys.sh ]; then
    echo "Regenerating API keys file..."
    APIKEY_WRITE=$(get_apikey_write)
    APIKEY_READ=$(get_apikey_read)
    cat > /home/ga/emoncms_apikeys.sh << APIKEYS_EOF
export EMONCMS_URL="${EMONCMS_URL}"
export EMONCMS_APIKEY_WRITE="${APIKEY_WRITE}"
export EMONCMS_APIKEY_READ="${APIKEY_READ}"
APIKEYS_EOF
    chmod 644 /home/ga/emoncms_apikeys.sh
    chown ga:ga /home/ga/emoncms_apikeys.sh
fi

# Clean up any pre-existing office_env inputs and feeds (idempotent)
APIKEY=$(get_apikey_write)

# Delete any existing office_env feeds
EXISTING_FEEDS=$(db_query "SELECT id FROM feeds WHERE tag='office_env'" 2>/dev/null || echo "")
if [ -n "$EXISTING_FEEDS" ]; then
    for fid in $EXISTING_FEEDS; do
        curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${fid}" >/dev/null 2>&1 || true
    done
    echo "Cleaned up existing office_env feeds"
fi

# Delete any existing office_env inputs
EXISTING_INPUTS=$(db_query "SELECT id FROM input WHERE nodeid='office_env'" 2>/dev/null || echo "")
if [ -n "$EXISTING_INPUTS" ]; then
    for iid in $EXISTING_INPUTS; do
        db_query "DELETE FROM input WHERE id=${iid}" 2>/dev/null || true
    done
    echo "Cleaned up existing office_env inputs"
fi

# Remove any old config file
rm -f /home/ga/sensor_config.json

# Record initial state
INITIAL_FEED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds" 2>/dev/null || echo "0")
INITIAL_INPUT_COUNT=$(db_query "SELECT COUNT(*) FROM input" 2>/dev/null || echo "0")
echo "$INITIAL_FEED_COUNT" > /tmp/initial_feed_count.txt
echo "$INITIAL_INPUT_COUNT" > /tmp/initial_input_count.txt

# Launch Firefox to Emoncms inputs page (provides visual confirmation of API actions)
# This helps the agent "see" the result of their API calls if they choose to check via UI
launch_firefox_to "http://localhost/input/view" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="