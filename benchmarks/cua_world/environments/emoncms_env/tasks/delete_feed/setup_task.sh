#!/bin/bash
# Task setup: delete_feed
# Ensures the 'Test Feed' exists before the agent deletes it.

source /workspace/scripts/task_utils.sh

echo "=== Setting up delete_feed task ==="

wait_for_emoncms

APIKEY=$(get_apikey_write)

# Ensure 'Test Feed' exists (recreate if it was previously deleted)
EXISTING=$(db_query "SELECT id FROM feeds WHERE name='Test Feed' AND userid=1" 2>/dev/null | head -1)
if [ -z "$EXISTING" ]; then
    CREATE_RESULT=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=Test+Feed&tag=test&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W")
    echo "Created 'Test Feed': ${CREATE_RESULT}"
    sleep 2
else
    echo "Test Feed already exists (id=${EXISTING})"
fi

# Navigate to Feeds list page
launch_firefox_to "http://localhost/feed/list" 5

# Take a starting screenshot
take_screenshot /tmp/task_delete_feed_start.png

echo "=== Task setup complete: delete_feed ==="
