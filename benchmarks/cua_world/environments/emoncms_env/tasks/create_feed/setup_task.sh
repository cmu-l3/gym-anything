#!/bin/bash
# Task setup: create_feed
# Navigates to the Feeds page so agent can create a new feed.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_feed task ==="

# Ensure Emoncms is responding
wait_for_emoncms

# Remove "Boiler Power" feed if it already exists (clean state)
EXISTING=$(db_query "SELECT id FROM feeds WHERE name='Boiler Power' AND userid=1" 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
    APIKEY=$(get_apikey_write)
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${EXISTING}" >/dev/null 2>&1 || true
    echo "Removed existing 'Boiler Power' feed (id=${EXISTING})"
fi

# Navigate to Feeds page
launch_firefox_to "http://localhost/feed/list" 5

# Take a starting screenshot
take_screenshot /tmp/task_create_feed_start.png

echo "=== Task setup complete: create_feed ==="
